---
omd: 0.1
brand: YOnLearn Hub
bootstrapped_at: 2026-07-12
---

# YOnLearn Hub design system

## Brand thesis
??? ? ?? AI ??? ??? ?? ??? ???, ???? ??? ??? ??? ?? ??? ????? ???.

## Tokens
- Navy `#09294F`: headings, primary actions, footer.
- Deep blue `#174F89`: links and informative emphasis.
- Teal `#00A89C`: focus, eyebrow labels, progress and positive emphasis.
- Mist `#F3F7FB`: quiet section background.
- Text `#10233F`, muted `#5C6F84`, border `#DCE6EF`.
- Radius: 10px controls, 14px cards, 20px promotional panels.
- Container: 1180px with one shared horizontal gutter.

## Typography and voice
Pretendard (SIL OFL) with system fallbacks. Copy is clear, respectful, action-oriented, and avoids inflated AI claims. Headings use compact negative tracking; body copy prioritizes Korean readability.

## Components and states
Search is the home page's primary action. Cards remain scannable with category, title, summary, and no more than two tags. Every asynchronous surface has loading, error, empty, and success feedback. Focus rings use translucent teal and never rely on color alone.

## Responsive and motion
Support 360px and larger. Four-column cards collapse to two and then one; navigation becomes a disclosure menu. Motion is limited to 180ms functional transitions and is removed under `prefers-reduced-motion`.
