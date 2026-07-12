# YOnLab public education content pack v1

Status: implemented for RC1 demonstration and verification.

This content pack is fictional sample data written by YOnLab for the YOnLearn Hub RC1 environment. It is not real operating data and must not be treated as approved curriculum, legal guidance, safety guidance, institutional policy, or licensed teaching material.

## Scope

The seed creates the following content when the database is empty:

| Entity | Count |
|---|---:|
| Categories | 10 |
| Tags | 45 |
| Resources | 100 |
| Notices | 18 |
| Articles / insights | 28 |
| FAQs | 45 |
| Inquiries | 15 |
| Users | 4 |
| Real attachments | 0 |

The resource pack is organized around early-childhood education portal themes: play activities, curriculum operation, observation and records, family partnership, safety and health, social-emotional support, digital practice, inclusive/multicultural support, center operations, and teacher growth.

## Clean-room statement

- All titles, summaries, article bodies, notices, FAQs, inquiries, and sample user records are YOnLab-authored fictional text.
- No i-Nuri original text, images, attachments, resource names, unique wording, layout, colors, file names, or source-site assets are used.
- No real institution name, real textbook name, real child/family/staff data, or real copyrighted attachment is included.
- Resource bodies may mention fictional metadata such as sample activity sheets, operation checklists, or observation templates, but the seed intentionally creates no actual attachment files.

## Operating caveat

Before production use, replace this pack with reviewed operating content. Required checks include copyright/license review, privacy review, accessibility review, educational appropriateness review, safety/legal review, and administrator approval workflow review.

## Verification

The regression test `backend/tests/test_seed_content_pack.py` checks counts, idempotency, representative category names, administrator presence, absence of real attachments, clean-room forbidden terms, and keyword density for play/observation/family/safety/digital searches.
