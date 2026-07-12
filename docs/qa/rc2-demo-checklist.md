# RC2 demo checklist

Use this checklist for the `v0.1.0-rc2` demonstration pass. The content is fictional YOnLab sample data for verification, not production operating content.

## Public portal

- [ ] Home screen feels content-rich and does not look empty.
- [ ] Primary search is visible and usable.
- [ ] Category/resource entry points are understandable.
- [ ] Mobile navigation opens and reaches Inquiry.

## Search terms

Confirm each search returns enough visible results and a mix of content types where applicable:

- [ ] `??`
- [ ] `??`
- [ ] `??`
- [ ] `??`
- [ ] `???`

## Resources

- [ ] Resource list shows many cards/items.
- [ ] Resource detail page has a substantial body, category, and tags.
- [ ] Resource metadata such as audience/type/recommended use context appears plausible.
- [ ] No real attachment download is required for the content pack demo.

## Content sections

- [ ] Notices list is populated.
- [ ] Insight/articles list is populated.
- [ ] FAQ list is populated and scannable.

## Member flow

- [ ] Login with demo learner account works.
- [ ] Bookmarking a resource works.
- [ ] Inquiry submission works.
- [ ] My page shows bookmark and inquiry history.

## Admin CMS

- [ ] Admin login works.
- [ ] Resource CMS list shows approximately 100 seeded resources.
- [ ] Notice CMS list shows approximately 18 notices.
- [ ] Article CMS list shows approximately 28 articles.
- [ ] FAQ CMS list shows approximately 45 FAQs.
- [ ] Inquiry CMS list shows approximately 15 sample inquiries.
- [ ] User CMS list shows 4 seeded users.
- [ ] Search/filter in representative CMS lists works.

## Responsive/mobile

- [ ] At 390px width, the home page has no horizontal overflow.
- [ ] At 390px width, navigation and search remain usable.
- [ ] At 390px width, resource cards and detail text remain readable.

## Docker demo

- [ ] Start Docker/Compose deployment.
- [ ] Open `http://localhost:8080`.
- [ ] Confirm HTTP 200 response and visible frontend.
- [ ] Confirm backend readiness through the verification script.
- [ ] Confirm isolated verification leaves no `yonlearn_verify_*` containers after cleanup.
