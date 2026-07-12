import os
from datetime import UTC, datetime, timedelta

from sqlalchemy import select

from app.database import Base, SessionLocal, engine
from app.models import FAQ, Article, Category, Inquiry, Notice, Resource, Role, Status, Tag, User
from app.security import hash_password

# YOnLab public education content pack v1.
# Fictional demo/verification data written by YOnLab. No i-Nuri original text,
# images, attachments, resource names, file names, colors, or distinctive copy is used.

PLAY = "\ub180\uc774"
ACTIVITY = "\ud65c\ub3d9"
EDU = "\uad50\uc721"
CURRICULUM = "\uacfc\uc815"
OPERATION = "\uc6b4\uc601"
OBSERVATION = "\uad00\ucc30"
RECORD = "\uae30\ub85d"
FAMILY = "\uac00\uc815"
LINK = "\uc5f0\uacc4"
SAFETY = "\uc548\uc804"
HEALTH = "\uac74\uac15"
EMOTION = "\uc815\uc11c"
SOCIAL = "\uc0ac\ud68c\uc131"
DIGITAL = "\ub514\uc9c0\ud138"
USE = "\ud65c\uc6a9"
INCLUSION = "\ud3ec\uc6a9"
MULTICULTURE = "\ub2e4\ubb38\ud654"
CENTER = "\uae30\uad00"
TEACHER = "\uad50\uc0ac"
GROWTH = "\uc131\uc7a5"
SUPPORT = "\uc9c0\uc6d0"
SAMPLE_MARK = "YOnLab \uc790\uccb4 \uc791\uc131 \uc0d8\ud50c"

CATEGORIES = [
    (f"{PLAY} {ACTIVITY}", "play-activities", f"{PLAY} \ud750\ub984\uc744 \uad00\ucc30\ud558\uace0 \ud655\uc7a5\ud558\ub294 \ud65c\ub3d9 \uc124\uacc4"),
    (f"{EDU}{CURRICULUM} {OPERATION}", "curriculum-operations", "\uc5f0\uac04\u00b7\uc6d4\uac04 \uc6b4\uc601\uacfc \ud65c\ub3d9 \uade0\ud615 \uc870\uc815"),
    (f"{OBSERVATION}\u00b7{RECORD}", "observation-records", "\uad00\ucc30 \uba54\ubaa8, \ud3ec\ud2b8\ud3f4\ub9ac\uc624, \ubc1c\ub2ec \uc9c0\uc6d0 \uae30\ub85d"),
    (f"{FAMILY} {LINK}", "family-partnership", "\ubd80\ubaa8 \uc18c\ud1b5\uacfc \uac00\uc815 \uc2e4\ucc9c \uc81c\uc548"),
    (f"{SAFETY}\u00b7{HEALTH}", "safety-health", "\uc548\uc804 \uc2b5\uad00, \uac10\uc5fc \uc608\ubc29, \uac74\uac15\ud55c \uc77c\uacfc"),
    (f"{EMOTION}\u00b7{SOCIAL}", "social-emotional", "\ub9c8\uc74c\ub3cc\ubd04, \ub610\ub798\uad00\uacc4, \uac08\ub4f1 \uc870\uc815"),
    (f"{DIGITAL} {USE}", "digital-practice", "\ub514\uc9c0\ud138 \ub3c4\uad6c\uc640 \ubbf8\ub514\uc5b4 \ub9ac\ud130\ub7ec\uc2dc\uc758 \uade0\ud615"),
    (f"{INCLUSION}\u00b7{MULTICULTURE}", "inclusive-multicultural", "\ub2e4\uc591\uc131, \uc811\uadfc\uc131, \ucc38\uc5ec \uc7a5\ubcbd \uc644\ud654"),
    (f"{CENTER} {OPERATION}", "center-operations", "\uc6b4\uc601 \uacc4\ud68d, \ud589\uc0ac, \ud611\uc5c5 \uccb4\uacc4"),
    (f"{TEACHER} {GROWTH}", "teacher-growth", "\uad50\uc0ac \uc5f0\uc218, \ub3d9\ub8cc \uc7a5\ud559, \ud68c\uace0 \ubb38\ud654"),
]

TAG_NAMES = [
    "\ubc14\uae65\ub180\uc774", "\uc2e4\ub0b4\ub180\uc774", "\uc5b8\uc5b4\ub180\uc774", "\uc218\u00b7\uacfc\ud559", "\uc608\uc220\uacbd\ud5d8",
    "\uc2e0\uccb4\ud65c\ub3d9", "\uc790\uc5f0\ud0d0\uc0c9", "\ud611\ub3d9\ub180\uc774", "\uc5ed\ud560\ub180\uc774", "\ub180\uc774\ud655\uc7a5",
    "\uc5f0\uac04\uacc4\ud68d", "\uc6d4\uac04\uacc4\ud68d", "\ud558\ub8e8\uc77c\uacfc", "\uc6b4\uc601\ud3c9\uac00", "\uad50\uc721\uacfc\uc815\ud68c\uc758",
    "\uad00\ucc30\uc77c\uc9c0", "\ud3ec\ud2b8\ud3f4\ub9ac\uc624", "\ubc1c\ub2ec\uc9c0\uc6d0", "\uae30\ub85d\uc591\uc2dd", "\ud3c9\uac00\ub8e8\ube0c\ub9ad",
    "\ubd80\ubaa8\uc18c\ud1b5", "\uac00\uc815\ud1b5\uc2e0\ubb38", "\uac00\uc815\ub180\uc774", "\uc0c1\ub2f4\uc900\ube44", "\uc9c0\uc5ed\uc5f0\uacc4",
    "\uc548\uc804\uad50\uc721", "\uac10\uc5fc\uc608\ubc29", "\uc751\uae09\ub300\uc751", "\uae09\uc2dd\uc704\uc0dd", "\uc2e4\uc678\uc548\uc804",
    "\ub9c8\uc74c\ub3cc\ubd04", "\ub610\ub798\uad00\uacc4", "\uac08\ub4f1\uc870\uc815", "\ubb38\uc81c\ud589\ub3d9\uc9c0\uc6d0", "\ud68c\ubcf5\ud0c4\ub825\uc131",
    "\ub514\uc9c0\ud138\ub3c4\uad6c", "\ubbf8\ub514\uc5b4\ub9ac\ud130\ub7ec\uc2dc", "AI\ud65c\uc6a9", "\uc811\uadfc\uc131", "\uc628\ub77c\uc778\uc18c\ud1b5",
    "\ub2e4\ubb38\ud654\uc774\ud574", "\uac1c\ubcc4\ud654\uc9c0\uc6d0", "\uc6b4\uc601\uacc4\ud68d", "\ud589\uc0ac\uc6b4\uc601", "\uad50\uc0ac\uc5f0\uc218",
]
TAGS = [(name, f"tag-{index + 1:02d}") for index, name in enumerate(TAG_NAMES)]

CATEGORY_TAG_INDEXES = {
    "play-activities": [0, 1, 2, 3, 4, 5, 7, 9],
    "curriculum-operations": [10, 11, 12, 13, 14, 19],
    "observation-records": [15, 16, 17, 18, 19, 23],
    "family-partnership": [20, 21, 22, 23, 24, 39],
    "safety-health": [25, 26, 27, 28, 29, 12],
    "social-emotional": [30, 31, 32, 33, 34, 7],
    "digital-practice": [35, 36, 37, 38, 39, 18],
    "inclusive-multicultural": [40, 41, 38, 17, 20, 24],
    "center-operations": [42, 10, 43, 25, 13, 14],
    "teacher-growth": [44, 14, 13, 19, 30, 37],
}

RESOURCE_TOPICS = [
    ("\uccab \uad00\ucc30", "\ud765\ubbf8\ub97c \uc0b4\ud53c\uace0 \ucd9c\ubc1c\uc810\uc744 \uc815\ub9ac\ud558\ub294 \uc790\ub8cc"),
    ("\ud658\uacbd \uad6c\uc131", "\uacf5\uac04\u00b7\uc790\ub8cc\u00b7\uc2dc\uac04\uc744 \uc870\uc815\ud558\ub294 \uc790\ub8cc"),
    ("\uc0c1\ud638\uc791\uc6a9 \ubb38\uc7a5", "\uad50\uc0ac\uac00 \ubc14\ub85c \uc0ac\uc6a9\ud560 \uc9c8\ubb38\uacfc \ubc18\uc751 \uc608\uc2dc"),
    ("\uc18c\uadf8\ub8f9 \uc6b4\uc601", "\uc18c\uadf8\ub8f9 \ud65c\ub3d9\uc744 \uc2dc\uc791\ud558\uace0 \ub9c8\ubb34\ub9ac\ud558\ub294 \uc790\ub8cc"),
    ("\uac1c\ubcc4 \uc9c0\uc6d0", "\uc544\uc774\ubcc4 \uc18d\ub3c4\uc640 \ud544\uc694\ub97c \ubc18\uc601\ud558\ub294 \uc790\ub8cc"),
    ("\uac00\uc815 \uc548\ub0b4", "\uac00\uc815\uacfc \uc774\uc5b4\uc9c0\ub294 \uc9e7\uc740 \uc2e4\ucc9c \uc81c\uc548"),
    ("\uc548\uc804 \uc810\uac80", "\uc548\uc804\u00b7\uac74\uac15 \uc694\uc18c\ub97c \ub193\uce58\uc9c0 \uc54a\ub3c4\ub85d \ub3d5\ub294 \uc790\ub8cc"),
    ("\ub514\uc9c0\ud138 \uade0\ud615", "\ub514\uc9c0\ud138 \ub3c4\uad6c\ub97c \ubaa9\uc801 \uc788\uac8c \uc4f0\ub294 \uc790\ub8cc"),
    ("\ud3ec\uc6a9 \uc124\uacc4", "\ub2e4\uc591\ud55c \ucc38\uc5ec \ubc29\uc2dd\uacfc \uc811\uadfc\uc131\uc744 \uace0\ub824\ud558\ub294 \uc790\ub8cc"),
    ("\ud68c\uace0 \uae30\ub85d", "\ud65c\ub3d9 \ud6c4 \ubc30\uc6c0\uacfc \ub2e4\uc74c \uc9c0\uc6d0 \ubc29\ud5a5\uc744 \uc815\ub9ac\ud558\ub294 \uc790\ub8cc"),
]
AUDIENCES = ["\uad50\uc0ac", "\uae30\uad00 \uc6b4\uc601\uc790", "\ud559\ubd80\ubaa8", "\ud1b5\ud569 \uc9c0\uc6d0\ud300"]
RESOURCE_TYPES = ["\ud65c\ub3d9 \uac00\uc774\ub4dc", "\uc6b4\uc601 \uccb4\ud06c\ub9ac\uc2a4\ud2b8", "\uad00\ucc30 \uae30\ub85d \uc591\uc2dd", "\uac00\uc815 \uc5f0\uacc4 \uc548\ub0b4", "\uad50\uc0ac \ud611\uc758 \uc790\ub8cc"]

NOTICE_TITLES = [
    "\uacf5\uacf5 \uad50\uc721\ud3ec\ud138\ud615 \ucf58\ud150\uce20 \ud329 v1 \uc2dc\uc5f0 \ub370\uc774\ud130 \uc548\ub0b4",
    "\ub180\uc774 \ud65c\ub3d9 \uc790\ub8cc \ubb36\uc74c \uc5c5\ub370\uc774\ud2b8",
    "\uad00\ucc30\u00b7\uae30\ub85d \uc790\ub8cc \uac80\uc0c9 \uac1c\uc120 \uc548\ub0b4",
    "\uac00\uc815 \uc5f0\uacc4 \uc548\ub0b4\ubb38 \ud65c\uc6a9 \uc720\uc758\uc0ac\ud56d",
    "\uc548\uc804\u00b7\uac74\uac15 \ucf58\ud150\uce20 \uc810\uac80 \uc8fc\uac04",
    "\uc815\uc11c\u00b7\uc0ac\ud68c\uc131 \uc9c0\uc6d0 \uc790\ub8cc \uacf5\uac1c",
    "\ub514\uc9c0\ud138 \ud65c\uc6a9 \uc790\ub8cc \uc774\uc6a9 \uc548\ub0b4",
    "\ud3ec\uc6a9\u00b7\ub2e4\ubb38\ud654 \uc790\ub8cc \uac80\ud1a0 \uc694\uccad",
    "\uae30\uad00 \uc6b4\uc601 \uccb4\ud06c\ub9ac\uc2a4\ud2b8 \uc5c5\ub370\uc774\ud2b8",
    "\uad50\uc0ac \uc131\uc7a5 \uc5f0\uc218 \uc0d8\ud50c \uc548\ub0b4",
    "\uac80\uc0c9\uc5b4 \ucd94\ucc9c \uae30\ub2a5 \ud65c\uc6a9 \uc548\ub0b4",
    "\ubd81\ub9c8\ud06c \uae30\ub2a5 \uc810\uac80 \uc548\ub0b4",
    "\uad00\ub9ac\uc790 CMS \ubaa9\ub85d \uac80\uc99d \uc548\ub0b4",
    "\ubb38\uc758 \uc751\ub300 \uc0d8\ud50c \ub370\uc774\ud130 \uc548\ub0b4",
    "\uac1c\uc778\uc815\ubcf4 \uc785\ub825 \uc8fc\uc758 \uc548\ub0b4",
    "\ucf58\ud150\uce20 \uc81c\uc548 \uc811\uc218 \uc548\ub0b4",
    "\uc2dc\uc2a4\ud15c \uc810\uac80 \uc608\uace0 \uc0d8\ud50c",
    "RC1 \uac80\uc99d\uc6a9 \ucf58\ud150\uce20 \uc6b4\uc601 \uba54\ubaa8",
]

ARTICLE_TOPICS = [
    "\ub180\uc774 \uae30\ubc18 \uad50\uc721\uc5d0\uc11c \uad00\ucc30 \uc9c8\ubb38\uc744 \uc138\uc6b0\ub294 \ubc29\ubc95",
    "\uc544\uc774\uc758 \ud765\ubbf8\ub97c \ub2e4\uc74c \ud65c\ub3d9\uc73c\ub85c \uc5f0\uacb0\ud558\ub294 \uae30\ub85d \uc2b5\uad00",
    "\uac00\uc815 \uc5f0\uacc4 \ubb38\uc7a5\uc744 \uc9e7\uace0 \ubd84\uba85\ud558\uac8c \uc4f0\ub294 \uc6d0\uce59",
    "\ub514\uc9c0\ud138 \ub3c4\uad6c\ub97c \ud65c\ub3d9 \ubaa9\uc801\uc5d0 \ub9de\uac8c \uc4f0\uae30",
    "\ub610\ub798 \uac08\ub4f1\uc744 \ubc30\uc6c0\uc758 \uc7a5\uba74\uc73c\ub85c \uc804\ud658\ud558\ub294 \ub300\ud654",
    "\uad50\uc2e4 \uc548\uc804 \uc810\uac80\uc744 \uc77c\uacfc \uc548\uc5d0 \ub123\ub294 \ubc95",
    "\ud3ec\uc6a9 \uad50\uc721\uc744 \uc704\ud55c \uc120\ud0dd\uc9c0\uc640 \uc811\uadfc\uc131 \uc124\uacc4",
    "\uad50\uc0ac \ud68c\uace0 \ud68c\uc758\ub97c \uc9e7\uace0 \uc9c0\uc18d \uac00\ub2a5\ud558\uac8c \uc6b4\uc601\ud558\uae30",
] * 4
ARTICLE_TOPICS = ARTICLE_TOPICS[:28]

FAQ_ITEMS = [(f"\uc0d8\ud50c FAQ {i + 1:02d}: {PLAY}\u00b7{OBSERVATION}\u00b7{FAMILY}\u00b7{SAFETY}\u00b7{DIGITAL} \uc790\ub8cc\ub294 \uc5b4\ub5bb\uac8c \ud65c\uc6a9\ud558\ub098\uc694?", f"{SAMPLE_MARK} FAQ\uc785\ub2c8\ub2e4. \uc2e4\uc81c \uc6b4\uc601 \uc804 \uc800\uc791\uad8c, \uac1c\uc778\uc815\ubcf4, \uad50\uc721 \uc801\ud569\uc131 \uac80\ud1a0\uac00 \ud544\uc694\ud569\ub2c8\ub2e4.") for i in range(45)]

INQUIRY_STATUSES = ["received", "in_progress", "resolved"]
SAMPLE_USERS = [
    ("learner@example.com", "\uc0d8\ud50c \uad50\uc0ac \uc0ac\uc6a9\uc790", Role.user, "DemoUser!234"),
    ("operator@example.com", "\uc0d8\ud50c \uae30\uad00 \uc6b4\uc601\uc790", Role.user, "OperatorUser!234"),
    ("parent@example.com", "\uc0d8\ud50c \ud559\ubd80\ubaa8 \uc0ac\uc6a9\uc790", Role.user, "ParentUser!234"),
]


def now_minus(days: int) -> datetime:
    return datetime.now(UTC) - timedelta(days=days)


def build_resource_body(category_name: str, category_focus: str, topic: str, topic_note: str, index: int) -> str:
    minutes = 15 + (index % 4) * 10
    level = ["\uae30\ucd08", "\ud655\uc7a5", "\ud611\uc758", "\uc810\uac80"][index % 4]
    situation = ["\uc0c8 \ud559\uae30 \uc801\uc751", "\uc6d4\uac04 \uacc4\ud68d \ud68c\uc758", "\uac00\uc815 \uc18c\ud1b5 \uc804", "\ud65c\ub3d9 \ud6c4 \ud68c\uace0", "\uc548\uc804 \uc810\uac80 \uc8fc\uac04"][index % 5]
    return (
        f"{SAMPLE_MARK} \ucf58\ud150\uce20\uc785\ub2c8\ub2e4. \uc2e4\uc81c \uc6b4\uc601 \uc790\ub8cc\uac00 \uc544\ub2c8\uba70 \uc678\ubd80 \uc6d0\ubb38, \uc774\ubbf8\uc9c0, \ucca8\ubd80\ud30c\uc77c, \uc2e4\uc81c \uc790\ub8cc\uba85\uc740 \uc0ac\uc6a9\ud558\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4.\n\n"
        f"\ud65c\uc6a9 \uc7a5\uba74: {category_name} \uc601\uc5ed\uc5d0\uc11c {category_focus}\uc744 \ub2e4\ub8f0 \ub54c {topic} \uad00\uc810\uc73c\ub85c \uc0b4\ud3b4\ubd05\ub2c8\ub2e4. "
        f"\ucd94\ucc9c \uc0c1\ud669\uc740 {situation}\uc774\uba70 \ub09c\uc774\ub3c4\ub294 {level}, \uc608\uc0c1 \ud65c\uc6a9 \uc2dc\uac04\uc740 \uc57d {minutes}\ubd84\uc785\ub2c8\ub2e4.\n\n"
        f"\uc9c4\ud589 \ud750\ub984: \uc544\uc774\ub4e4\uc758 \ud765\ubbf8\ub97c \uad00\ucc30\ud558\uace0, {topic_note}\uc744 \uae30\uc900\uc73c\ub85c \uc9c8\ubb38\uc744 \uc900\ube44\ud569\ub2c8\ub2e4. "
        f"{PLAY}, {OBSERVATION}, {FAMILY}, {SAFETY}, {DIGITAL} \ud0a4\uc6cc\ub4dc\ub97c \ud568\uaed8 \ubcf4\uba74 \uad50\uc0ac \ud611\uc758, \ubcf4\ud638\uc790 \uc548\ub0b4, \uae30\uad00 \ud68c\uc758\uc5d0 \ub2e4\ub978 \ubc29\uc2dd\uc73c\ub85c \ud65c\uc6a9\ud560 \uc218 \uc788\uc2b5\ub2c8\ub2e4. "
        "\uc0d8\ud50c \ud65c\ub3d9\uc9c0, \uc6b4\uc601 \uccb4\ud06c\ub9ac\uc2a4\ud2b8, \uad00\ucc30 \uae30\ub85d \uc591\uc2dd \uac19\uc740 \uac00\uc0c1 \uba54\ud0c0\ub370\uc774\ud130\ub9cc \ub450\uace0 \uc2e4\uc81c \ucca8\ubd80\ud30c\uc77c\uc740 \ud3ec\ud568\ud558\uc9c0 \uc54a\uc2b5\ub2c8\ub2e4."
    )


def seed() -> None:
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        if db.scalar(select(Category)):
            print("Seed data already exists.")
            return

        categories = [Category(name=name, slug=slug) for name, slug, _ in CATEGORIES]
        tags = [Tag(name=name, slug=slug) for name, slug in TAGS]
        db.add_all(categories + tags)
        db.flush()

        category_by_slug = {category.slug: category for category in categories}
        tags_by_index = {index: tag for index, tag in enumerate(tags)}

        for c_index, (category_name, category_slug, category_focus) in enumerate(CATEGORIES):
            category = category_by_slug[category_slug]
            tag_indexes = CATEGORY_TAG_INDEXES[category_slug]
            for r_index, (topic, topic_note) in enumerate(RESOURCE_TOPICS):
                ordinal = c_index * len(RESOURCE_TOPICS) + r_index
                selected_tags = [tags_by_index[tag_indexes[r_index % len(tag_indexes)]], tags_by_index[tag_indexes[(r_index + 2) % len(tag_indexes)]]]
                title = f"{category_name} {topic} {SUPPORT} \uc790\ub8cc {r_index + 1:02d}"
                summary = f"{category_name} \ub9e5\ub77d\uc5d0\uc11c {topic_note}\uc785\ub2c8\ub2e4. {PLAY}\u00b7{OBSERVATION}\u00b7{FAMILY}\u00b7{SAFETY}\u00b7{DIGITAL} \uad00\uc810\uc744 \ud568\uaed8 \ub2f4\uc740 {SAMPLE_MARK}\uc785\ub2c8\ub2e4."
                db.add(Resource(title=title, summary=summary, body=build_resource_body(category_name, category_focus, topic, topic_note, ordinal), audience=AUDIENCES[ordinal % len(AUDIENCES)], resource_type=RESOURCE_TYPES[ordinal % len(RESOURCE_TYPES)], category=category, tags=selected_tags, status=Status.published, featured=ordinal < 12, published_at=now_minus(ordinal)))

        for index, title in enumerate(NOTICE_TITLES):
            body = f"{SAMPLE_MARK} \uacf5\uc9c0\uc785\ub2c8\ub2e4. {PLAY}, {OBSERVATION}, {FAMILY}, {SAFETY}, {DIGITAL} \uac80\uc0c9\uacfc CMS \uc2dc\uc5f0\uc744 \uc704\ud55c \ud5c8\uad6c \uc548\ub0b4\uc774\uba70 \uc2e4\uc81c \uc6b4\uc601 \uc77c\uc815\uc774 \uc544\ub2d9\ub2c8\ub2e4."
            db.add(Notice(title=title, body=body, status=Status.published, published_at=now_minus(index)))

        for index, title in enumerate(ARTICLE_TOPICS):
            summary = f"{title}\uc5d0 \ub300\ud55c {SAMPLE_MARK} \uc778\uc0ac\uc774\ud2b8\uc785\ub2c8\ub2e4."
            body = f"{SAMPLE_MARK} \ucf58\ud150\uce20\uc785\ub2c8\ub2e4. \uc774 \uae00\uc740 {title}\uc744 \uc8fc\uc81c\ub85c {PLAY}, {OBSERVATION}, {FAMILY}, {SAFETY}, {DIGITAL}, {INCLUSION} \uad00\uc810\uc744 \uc5f0\uacb0\ud569\ub2c8\ub2e4. \uc6b4\uc601 \uc804 \uc800\uc791\uad8c, \uac1c\uc778\uc815\ubcf4, \uad50\uc721 \uc801\ud569\uc131 \uac80\ud1a0\uac00 \ud544\uc694\ud569\ub2c8\ub2e4."
            db.add(Article(title=title, summary=summary, body=body, status=Status.published, published_at=now_minus(index)))

        for index, (question, answer) in enumerate(FAQ_ITEMS):
            db.add(FAQ(question=question, answer=answer, order=index + 1, status=Status.published))

        admin_email = (os.getenv("ADMIN_EMAIL") or "admin@example.com").lower()
        admin_password = os.getenv("ADMIN_PASSWORD") or "AdminPass!123"
        db.add(User(email=admin_email, name="\uc0d8\ud50c \uad00\ub9ac\uc790", password_hash=hash_password(admin_password), role=Role.admin))
        sample_user_rows = []
        for email, name, role, password in SAMPLE_USERS:
            user = User(email=email, name=name, password_hash=hash_password(password), role=role)
            sample_user_rows.append(user)
            db.add(user)
        db.flush()
        user_by_email = {user.email: user for user in sample_user_rows}

        inquiry_subjects = ["\uc790\ub8cc \uc774\uc6a9 \ubb38\uc758", "\uacc4\uc815 \ub85c\uadf8\uc778 \ubb38\uc758", "\uae30\uad00 \uad00\ub9ac\uc790 \uad8c\ud55c \ubb38\uc758", "\ucf58\ud150\uce20 \uc81c\uc548", "\uc624\ub958 \uc2e0\uace0"]
        inquiry_emails = ["learner@example.com", "operator@example.com", "parent@example.com"]
        for index in range(15):
            email = inquiry_emails[index % len(inquiry_emails)]
            user = user_by_email.get(email)
            subject = f"{inquiry_subjects[index % len(inquiry_subjects)]} {index + 1:02d}"
            message = f"{SAMPLE_MARK} \ubb38\uc758\uc785\ub2c8\ub2e4. {PLAY}, {OBSERVATION}, {FAMILY}, {SAFETY}, {DIGITAL} \uc790\ub8cc \ud65c\uc6a9\uacfc \uc6b4\uc601 \ud750\ub984\uc744 \ud655\uc778\ud558\ub824\ub294 \uc2dc\uc5f0\uc6a9 \ubb38\uc758\uc785\ub2c8\ub2e4."
            db.add(Inquiry(user_id=user.id if user else None, email=email, subject=subject, message=message, status=INQUIRY_STATUSES[index % len(INQUIRY_STATUSES)], admin_note="\uc0d8\ud50c \uc751\ub300 \uba54\ubaa8", privacy_agreed=True))

        db.commit()
        print("Seed complete: 10 categories, 45 tags, 100 resources, 18 notices, 28 articles, 45 FAQs, 15 inquiries, 4 users.")


if __name__ == "__main__":
    seed()
