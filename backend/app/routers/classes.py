"""Classes and students: reading them, and the four acts that change them.

**Who may do what, since 2026-09-20.** The principal is the school's admin and
does all four outright — create a class, delete one, register a pupil, remove
one. A teacher registers a pupil outright too (since 2026-09-27; the principal
is notified). The other three a teacher may start, but what they produce is a
request for the principal to answer; see [app.approvals] for why nothing else
changes until it is answered.

The endpoints do not fork by role at the top and run two implementations. Each
one decides who is asking, then either performs the change or records the ask,
and returns the **same** [ActionResult] shape either way — `status: "done"`
with the thing, or `status: "pending"` with the request. The app reads one
response and does not have to reproduce the rule about who needs approval in
order to know what happened.

Reading is unchanged in shape and widened in one place: a teacher's classes
are now the ones they own **plus the ones they were added to as a
co-teacher**, which is [app.access.teacher_class_ids] and nothing else.
"""

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import approvals, notifications, school
from app.access import (
    guardian_class_ids,
    guardian_student_ids,
    is_guardian,
    is_principal,
    owns_class,
    readable_class,
    readable_student,
    reader_scope,
    require_principal,
    require_staff,
    require_teacher,
    taught_class,
    teacher_class_ids,
)
from app.database import class_roster
from app.deps import CurrentUser, DbSession
from app.models import (
    REQUEST_CLASS_CREATE,
    REQUEST_CLASS_DELETE,
    REQUEST_PENDING,
    REQUEST_STUDENT_REMOVE,
    ChangeRequest,
    ClassTeacher,
    SchoolClass,
    Student,
    StudentMapping,
    Teacher,
    User,
)
from app.schemas import (
    ActionResult,
    ChangeRequestOut,
    ClassCreateRequest,
    ClassOut,
    ClassTeacherOut,
    ClassTeachersAssignRequest,
    ClassTeacherAssignRequest,
    ClassUpdateRequest,
    RosterEntry,
    StudentCreateRequest,
    StudentOut,
    StudentUpdateRequest,
)

router = APIRouter(tags=["classes"])


# --- Shared plumbing ----------------------------------------------------------


def _attach_teachers(db: Session, items: list[ClassOut]) -> list[ClassOut]:
    """Fills in `teachers` on a list of classes, class teacher first.

    Two queries for any number of classes rather than two per class. The
    dashboard asks for every class in the school in one call, and a per-class
    lookup there is the classic N+1 — invisible with four classes and painful
    with forty.
    """
    if not items:
        return items

    class_ids = [item.class_id for item in items]
    by_class: dict[str, list[ClassTeacherOut]] = {
        class_id: [] for class_id in class_ids
    }

    owners = db.execute(
        select(SchoolClass.class_id, Teacher.teacher_id, User.full_name)
        .join(Teacher, Teacher.teacher_id == SchoolClass.teacher_id)
        .join(User, User.user_id == Teacher.user_id)
        .where(SchoolClass.class_id.in_(class_ids))
    ).all()
    for class_id, teacher_id, full_name in owners:
        by_class[class_id].append(
            ClassTeacherOut(
                teacher_id=teacher_id,
                full_name=full_name,
                is_class_teacher=True,
            )
        )

    co_teachers = db.execute(
        select(ClassTeacher.class_id, Teacher.teacher_id, User.full_name)
        .join(Teacher, Teacher.teacher_id == ClassTeacher.teacher_id)
        .join(User, User.user_id == Teacher.user_id)
        .where(ClassTeacher.class_id.in_(class_ids))
        .order_by(User.full_name)
    ).all()
    for class_id, teacher_id, full_name in co_teachers:
        by_class[class_id].append(
            ClassTeacherOut(
                teacher_id=teacher_id,
                full_name=full_name,
                is_class_teacher=False,
            )
        )

    for item in items:
        item.teachers = by_class.get(item.class_id, [])
    return items


def _one_class_out(db: Session, class_id: str) -> ClassOut:
    return _attach_teachers(
        db, school.classes_out(db, SchoolClass.class_id == class_id)
    )[0]


def _reject_duplicate_pending(
    db: Session,
    teacher: Teacher,
    kind: str,
    *,
    class_id: str | None = None,
    student_id: str | None = None,
    class_name: str | None = None,
) -> None:
    """Stops the same teacher asking twice for the same thing.

    Without it, a teacher who taps Delete again because nothing appeared to
    happen — which is exactly what "nothing changes until approved" looks like
    from their side — files a second request, and the principal gets a queue
    of duplicates to work out.

    Matched on the target where there is one, and on the class name for a
    creation, which has no target yet.
    """
    query = select(ChangeRequest).where(
        ChangeRequest.status == REQUEST_PENDING,
        ChangeRequest.kind == kind,
        ChangeRequest.requested_by_teacher_id == teacher.teacher_id,
    )
    if class_id is not None:
        query = query.where(ChangeRequest.class_id == class_id)
    if student_id is not None:
        query = query.where(ChangeRequest.student_id == student_id)

    for existing in db.scalars(query):
        if class_name is not None:
            asked_for = (existing.payload or {}).get("name", "")
            if asked_for.strip().lower() != class_name.strip().lower():
                continue
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            detail=(
                f"You have already asked for {existing.summary}. "
                "It is still waiting for the principal."
            ),
        )


def _pending_result(request: ChangeRequest) -> ActionResult:
    return ActionResult(
        status="pending",
        detail=f"Sent to the principal for approval: {request.summary}.",
        request=ChangeRequestOut.model_validate(request),
    )


# --- Classes ------------------------------------------------------------------


@router.get("/classes", response_model=list[ClassOut])
def list_classes(user: CurrentUser, db: DbSession) -> list[ClassOut]:
    """The classes this account may see.

    Every class there is, for the principal. For a teacher, the ones they take
    — owned **or** co-taught, which is the change 0006 brought. For a parent,
    the classes their children are in: usually one, two if they have children
    in different years.
    """
    if is_guardian(user):
        class_ids = guardian_class_ids(db, user)
        # An empty list, not an error. A parent whose account has not been
        # linked yet has done nothing wrong and can do nothing about it.
        if not class_ids:
            return []
        return _attach_teachers(
            db, school.classes_out(db, SchoolClass.class_id.in_(class_ids))
        )

    teacher = reader_scope(db, user)

    if teacher is None:
        return _attach_teachers(db, school.classes_out(db))

    class_ids = teacher_class_ids(db, teacher)
    if not class_ids:
        return []
    return _attach_teachers(
        db, school.classes_out(db, SchoolClass.class_id.in_(class_ids))
    )


@router.post(
    "/classes", response_model=ActionResult, status_code=status.HTTP_201_CREATED
)
def create_class(
    payload: ClassCreateRequest,
    user: CurrentUser,
    db: DbSession,
    response: Response,
) -> ActionResult:
    """Adds a class, or asks for one.

    The principal's goes straight in, under the teacher they named or under
    nobody at all — an unassigned class is a real thing in August. A teacher's
    becomes a request, filed under themselves; the `teacher_id` field is
    ignored for them, because a field that let a teacher file a class under a
    colleague would be a way to put work on somebody else's dashboard.

    The duplicate-name check runs now **and** again at approval. Now, so a
    teacher is not told "pending" for something that cannot succeed; again,
    because the name may be taken in between.
    """
    if is_principal(user):
        if payload.teacher_id is not None and db.get(Teacher, payload.teacher_id) is None:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, detail="Teacher not found"
            )

        school_class = school.create_class(
            db, teacher_id=payload.teacher_id, payload=payload
        )
        school.commit_or_409(
            db,
            f'A class called "{payload.name}" already exists, or the class '
            "file lists the same student twice",
        )
        created = _one_class_out(db, school_class.class_id)
        return ActionResult(
            status="done",
            detail=f"{created.name} added",
            school_class=created,
        )

    teacher = require_teacher(db, user)
    school.reject_duplicate_class_name(db, teacher.teacher_id, payload.name)
    _reject_duplicate_pending(
        db, teacher, REQUEST_CLASS_CREATE, class_name=payload.name
    )

    request = approvals.raise_request(
        db,
        teacher=teacher,
        asked_by=user,
        kind=REQUEST_CLASS_CREATE,
        summary=approvals.class_create_summary(payload.name),
        # The teacher's own id is not stored in the payload: the request is
        # filed under them already, and a second copy is a second thing that
        # could disagree.
        payload=payload.model_dump(mode="json", exclude={"teacher_id"}),
    )
    db.commit()
    db.refresh(request)

    response.status_code = status.HTTP_202_ACCEPTED
    return _pending_result(request)


@router.patch("/classes/{class_id}", response_model=ClassOut)
def update_class(
    class_id: str,
    payload: ClassUpdateRequest,
    user: CurrentUser,
    db: DbSession,
) -> ClassOut:
    """Renames or recolours a class. No approval, by decision.

    Renaming is not on the approval list and should not be: it is reversible
    in one tap, it destroys nothing, and a queue filled with colour changes is
    a queue the principal stops reading — which is what would make the
    deletions in it dangerous.

    The **class teacher** or the principal. A co-teacher is refused: renaming
    the class out from under the person answerable for it is a surprise
    nobody asked for.
    """
    if is_principal(user):
        school_class = db.get(SchoolClass, class_id)
        if school_class is None:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, detail="Class not found"
            )
    else:
        teacher = require_teacher(db, user)
        school_class = taught_class(db, teacher, class_id)
        if not owns_class(teacher, school_class):
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                detail=(
                    "Only the class teacher or the principal can rename or "
                    "recolour a class."
                ),
            )

    if payload.name is not None:
        school.reject_duplicate_class_name(
            db, school_class.teacher_id, payload.name, ignore_id=class_id
        )
        school_class.name = payload.name
    if payload.color_slot is not None:
        school_class.color_slot = payload.color_slot

    school.commit_or_409(db, f'A class called "{payload.name}" already exists')
    return _one_class_out(db, class_id)


@router.delete("/classes/{class_id}", response_model=ActionResult)
def delete_class(
    class_id: str, user: CurrentUser, db: DbSession, response: Response
) -> ActionResult:
    """Deletes a class and its students, or asks to.

    200 with `status: "done"` for the principal, 202 with `status: "pending"`
    for a teacher. Not 204 any more: a teacher's delete now has something to
    say back, and one endpoint that sometimes has a body and sometimes does
    not is worse to consume than one that always does.

    The app writes the class's `.xlsx` archive before calling this and only
    calls it if the file was really saved. That still holds for the teacher's
    path — they archive, then ask — so an approval that comes through tomorrow
    finds the file already written.
    """
    student_count = (
        db.scalar(
            select(func.count())
            .select_from(Student)
            .where(Student.class_id == class_id)
        )
        or 0
    )

    if is_principal(user):
        school_class = db.get(SchoolClass, class_id)
        if school_class is None:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND, detail="Class not found"
            )
        name = school_class.name
        school.delete_class(db, school_class)
        db.commit()
        return ActionResult(status="done", detail=f"{name} deleted")

    teacher = require_teacher(db, user)
    school_class = taught_class(db, teacher, class_id)
    _reject_duplicate_pending(
        db, teacher, REQUEST_CLASS_DELETE, class_id=class_id
    )

    request = approvals.raise_request(
        db,
        teacher=teacher,
        asked_by=user,
        kind=REQUEST_CLASS_DELETE,
        summary=approvals.class_delete_summary(school_class.name, student_count),
        class_id=class_id,
    )
    db.commit()
    db.refresh(request)

    response.status_code = status.HTTP_202_ACCEPTED
    return _pending_result(request)


@router.get("/classes/{class_id}/roster", response_model=list[RosterEntry])
def class_roster_for(class_id: str, user: CurrentUser, db: DbSession) -> list:
    """The class as a table: class id, class name, roll number, student name.

    **Staff only**, and the `require_staff` line is the whole reason. A linked
    parent can reach their child's class now, and `readable_class` on its own
    would have handed them this — which is every pupil in the class by name
    and roll number, i.e. a list of other people's children.
    """
    require_staff(db, user, action="read the class roster")
    readable_class(db, user, class_id)
    return list(
        db.execute(
            select(class_roster)
            .where(class_roster.c.class_id == class_id)
            .order_by(class_roster.c.roll_number)
        ).mappings()
    )


# --- Who teaches a class ------------------------------------------------------


@router.put("/classes/{class_id}/teachers", response_model=ClassOut)
def set_class_teachers(
    class_id: str,
    payload: ClassTeachersAssignRequest,
    user: CurrentUser,
    db: DbSession,
) -> ClassOut:
    """Sets who teaches a class. The principal's call, and the whole set.

    This is the "Add teacher" picker on the class screen: a list of the
    school's teachers, the chosen ones highlighted, several at a time. It
    sends what it wants the answer to be, not a difference — an unhighlighted
    name that stayed assigned would be the obvious bug, and the one nobody
    notices until a register turns up on the wrong dashboard.

    **The class teacher is preserved.** If the class already has one and they
    are still in the set, they stay the class teacher and everyone else is a
    co-teacher; otherwise the first id listed takes the role. Without that
    rule, reordering a list of checkboxes would quietly move who is
    answerable for the room.

    An empty list unassigns the class. That is a legitimate end state — the
    same one a class is created in — not an error to refuse.
    """
    require_principal(user, action="choose who teaches a class")

    school_class = db.get(SchoolClass, class_id)
    if school_class is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Class not found")

    wanted = list(payload.teacher_ids)
    if wanted:
        found = set(
            db.scalars(
                select(Teacher.teacher_id).where(
                    Teacher.teacher_id.in_(wanted)
                )
            )
        )
        missing = [
            teacher_id for teacher_id in wanted if teacher_id not in found
        ]
        if missing:
            raise HTTPException(
                status.HTTP_404_NOT_FOUND,
                detail=f"Teacher not found: {', '.join(missing)}",
            )

    # Who holds the room. The sitting class teacher keeps it if they are still
    # on the list; otherwise it falls to whoever is first.
    if school_class.teacher_id in wanted:
        class_teacher = school_class.teacher_id
    else:
        class_teacher = wanted[0] if wanted else None

    # A class the receiving teacher already has a same-named class of cannot
    # be handed to them: uq_classes_teacher_name is per teacher. Checked with
    # its own wording, because "a class called X already exists" reads on this
    # endpoint as though the principal had the clash — the clash is on the
    # teacher receiving it, and naming them is what sends the reader to the
    # right place.
    if class_teacher is not None and class_teacher != school_class.teacher_id:
        _reject_name_clash_for(db, class_teacher, school_class)

    school_class.teacher_id = class_teacher

    db.query(ClassTeacher).filter(ClassTeacher.class_id == class_id).delete()
    for teacher_id in wanted:
        # The class teacher is not repeated in class_teachers: one fact, one
        # place. teacher_class_ids unions the two halves for reading.
        if teacher_id == class_teacher:
            continue
        db.add(
            ClassTeacher(
                class_id=class_id,
                teacher_id=teacher_id,
                assigned_by_user_id=user.user_id,
            )
        )

    school.commit_or_409(
        db, f'A teacher here already has a class called "{school_class.name}"'
    )
    return _one_class_out(db, class_id)


def _reject_name_clash_for(
    db: Session, teacher_id: str, school_class: SchoolClass
) -> None:
    clash = db.scalar(
        select(SchoolClass.name).where(
            SchoolClass.teacher_id == teacher_id,
            func.lower(SchoolClass.name) == func.lower(school_class.name),
            SchoolClass.class_id != school_class.class_id,
        )
    )
    if clash is None:
        return

    teacher = db.get(Teacher, teacher_id)
    account = db.get(User, teacher.user_id) if teacher else None
    who = account.full_name if account else teacher_id
    raise HTTPException(
        status.HTTP_409_CONFLICT,
        detail=f'{who} already has a class called "{clash}"',
    )


@router.patch("/classes/{class_id}/teacher", response_model=ClassOut)
def assign_class_teacher(
    class_id: str,
    payload: ClassTeacherAssignRequest,
    user: CurrentUser,
    db: DbSession,
) -> ClassOut:
    """Names the class teacher — the one answerable for the room.

    Kept alongside [set_class_teachers], which sets the whole set, because the
    two answer different questions: "who takes this class" is a list, "who is
    the class teacher" is one person. A picker that could only send a list
    would have to encode the second question as an ordering, which is exactly
    the fragility the preserve rule in `set_class_teachers` exists to avoid.

    This **moves** the class: the previous class teacher loses it, which is
    what it has meant since phase 4 and what the dashboards either side of it
    show. If the named teacher was a co-teacher, they are promoted rather than
    listed twice — one fact, one place.

    **The students move with the class.** They belong to the class, not to the
    teacher, so nothing about them changes — which is why this is safe to do
    mid-term. Attendance already taken keeps the teacher who took it.
    """
    require_principal(user, action="assign a class to a teacher")

    school_class = db.get(SchoolClass, class_id)
    if school_class is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Class not found")

    teacher = db.get(Teacher, payload.teacher_id)
    if teacher is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Teacher not found")

    if teacher.teacher_id == school_class.teacher_id:
        # Already theirs. Idempotent rather than an error — the end state is
        # the one that was asked for.
        return _one_class_out(db, class_id)

    _reject_name_clash_for(db, teacher.teacher_id, school_class)

    # Promoted out of the co-teacher list if they were on it, so they are not
    # recorded in both halves.
    db.query(ClassTeacher).filter(
        ClassTeacher.class_id == class_id,
        ClassTeacher.teacher_id == teacher.teacher_id,
    ).delete()

    # **The outgoing class teacher is dropped, not demoted.** This endpoint
    # moves a class, and has since phase 4: it leaves one teacher's dashboard
    # and joins another's. Quietly leaving them on as a co-teacher would mean
    # a reassigned class never actually left anyone — use PUT
    # /classes/{id}/teachers to say "both of them", which is what that
    # endpoint is for.
    school_class.teacher_id = teacher.teacher_id
    school.commit_or_409(
        db, f'That teacher already has a class called "{school_class.name}"'
    )
    return _one_class_out(db, class_id)


# --- Students -----------------------------------------------------------------


@router.get("/students", response_model=list[StudentOut])
def list_students(user: CurrentUser, db: DbSession) -> list[StudentOut]:
    # Every student at once rather than per class: the dashboard shows a count
    # on every tile, so it needs them all anyway, and one request beats nine.

    # A parent gets their own children and nobody else's — which is also what
    # the student dashboard's "which child am I looking at?" list is built
    # from, since a parent may have two at the school.
    if is_guardian(user):
        student_ids = guardian_student_ids(db, user)
        if not student_ids:
            return []
        return school.students_out(db, Student.student_id.in_(student_ids))

    teacher = reader_scope(db, user)

    # The principal has access to every student in the school — one of the
    # things the role is for.
    if teacher is None:
        return school.students_out(db)

    # By class id, not by class_roster.teacher_id. That column is the class's
    # **owner**, so filtering on it would hide every pupil in a class this
    # teacher co-teaches — the exact gap class_teachers was added to close.
    class_ids = teacher_class_ids(db, teacher)
    if not class_ids:
        return []
    return school.students_out(db, Student.class_id.in_(class_ids))


@router.post(
    "/students", response_model=ActionResult, status_code=status.HTTP_201_CREATED
)
def create_student(
    payload: StudentCreateRequest,
    user: CurrentUser,
    db: DbSession,
) -> ActionResult:
    """Registers a pupil. Outright, for the principal **and** for a teacher.

    **Staff only**, and explicitly so. Once a linked parent could reach their
    child's class through `readable_class`, this route let them register
    pupils into it — registration is not a parent's act, and a class anyone
    can add children to is not a register.

    The principal registers into any class in the school. A teacher registers
    into any class they take; the class is resolved through their own scope,
    so a class id from elsewhere reads 404 rather than telling them it exists.

    **A teacher's registration stopped being a request on 2026-09-27.** Adding
    a pupil destroys nothing and is undone by removing them, which still
    needs the principal's approval — so the approval step was guarding the
    cheap direction and making a teacher wait a day to take a register for a
    new child. The principal is told instead: a notice with no `request_id`,
    so it carries no Approve or Reject, because there is nothing to decide.

    `REQUEST_STUDENT_ADD` stays a valid kind. Requests raised before the
    change are still in the queue and can still be answered.
    """
    require_staff(db, user, action="register a student")
    school_class = readable_class(db, user, payload.class_id)

    # Resolved before anything is written: an account that is staff but has no
    # teacher row is refused here rather than after the pupil exists.
    principal = is_principal(user)
    if not principal:
        require_teacher(db, user)

    student = school.create_student(
        db, school_class=school_class, payload=payload
    )

    if not principal:
        # In the same transaction as the pupil, so a registration that fails
        # to save cannot leave a notice behind saying it happened.
        notifications.notify_principals(
            db,
            message=notifications.student_registered_message(
                teacher_name=user.full_name,
                student_name=payload.name,
                class_name=school_class.name,
            ),
            source=user.full_name,
        )

    school.commit_or_409(
        db,
        f"{payload.name} is already registered in {school_class.name} "
        "with the same date of birth, address, and parents' details",
    )
    created = school.students_out(
        db, Student.student_id == student.student_id
    )[0]
    return ActionResult(
        status="done",
        detail=f"{created.name} added to {school_class.name}",
        student=created,
    )


_MOBILE_FIELDS = (
    ("mother_mobile", "mother's mobile"),
    ("father_mobile", "father's mobile"),
    ("guardian_mobile", "guardian's mobile"),
)


@router.patch("/students/{student_id}", response_model=ActionResult)
def update_student(
    student_id: str,
    payload: StudentUpdateRequest,
    user: CurrentUser,
    db: DbSession,
) -> ActionResult:
    """Edits a pupil's details. Outright, for a teacher of the class and for
    the principal.

    No approval: an edit destroys nothing that another edit cannot put back.
    Removing the pupil is the act that waits for the principal, and it stays
    on `DELETE`.

    **A changed mobile number notifies the pupil's linked parent accounts**,
    because a number on a child's record is how the school reaches the family,
    and the family should not find out it changed by missing a call. Raised in
    the same transaction as the edit, so a save that fails leaves no notice.
    """
    require_staff(db, user, action="edit a pupil's details")
    student = readable_student(db, user, student_id)
    school_class = db.get(SchoolClass, student.class_id)

    changes = [
        (label, getattr(payload, field))
        for field, label in _MOBILE_FIELDS
        if getattr(payload, field) != getattr(student, field)
    ]

    def mapped_accounts() -> set[str]:
        return set(
            db.scalars(
                select(StudentMapping.user_id).where(
                    StudentMapping.student_id == student_id
                )
            )
        )

    # Read before saving: the save re-maps the pupil by number, and the parent
    # whose number was replaced is exactly who most needs telling.
    mapped_before = mapped_accounts()

    school.update_student(
        db, student=student, school_class=school_class, payload=payload
    )

    if changes:
        guardian_ids = sorted(mapped_before | mapped_accounts())
        message = notifications.student_mobile_changed_message(
            editor_name=user.full_name,
            student_name=payload.name,
            changes=changes,
        )
        for guardian_id in guardian_ids:
            notifications.notify_user(
                db, user_id=guardian_id, message=message, source=user.full_name
            )

    school.commit_or_409(
        db,
        f"{payload.name} is already registered in {school_class.name} "
        "with the same date of birth, address, and parents' details",
    )
    updated = school.students_out(db, Student.student_id == student_id)[0]
    return ActionResult(
        status="done",
        detail=f"{updated.name}'s details saved",
        student=updated,
    )


@router.delete("/students/{student_id}", response_model=ActionResult)
def delete_student(
    student_id: str, user: CurrentUser, db: DbSession, response: Response
) -> ActionResult:
    """Removes a pupil from the school, or asks to.

    The principal's outright; a teacher's by request. This is the one of the
    four where the approval step earns itself most obviously — a pupil removed
    takes their attendance history with them, and there is no class file to
    restore them from the way there is for a class.

    **Staff only.** A parent reaching their own child through
    `readable_student` must not be able to delete them.
    """
    require_staff(db, user, action="remove a pupil")
    student = readable_student(db, user, student_id)
    school_class = db.get(SchoolClass, student.class_id)
    class_name = school_class.name if school_class else student.class_id

    if is_principal(user):
        name = student.name
        school.delete_student(db, student)
        db.commit()
        return ActionResult(
            status="done", detail=f"{name} removed from {class_name}"
        )

    teacher = require_teacher(db, user)
    _reject_duplicate_pending(
        db, teacher, REQUEST_STUDENT_REMOVE, student_id=student_id
    )

    request = approvals.raise_request(
        db,
        teacher=teacher,
        asked_by=user,
        kind=REQUEST_STUDENT_REMOVE,
        summary=approvals.student_remove_summary(student.name, class_name),
        class_id=student.class_id,
        student_id=student_id,
    )
    db.commit()
    db.refresh(request)

    response.status_code = status.HTTP_202_ACCEPTED
    return _pending_result(request)
