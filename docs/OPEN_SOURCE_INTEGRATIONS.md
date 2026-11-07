# Open-source Islamic resources and attribution

Qalam Muslim retains its original Aya-derived application architecture and adds selected Islamic learning resources and locally implemented worship tools. This document records the upstream projects reviewed or used for this expansion.

## Data included in the application

### Forty Nawawi Hadith — Arabic matn and citations

- Upstream: https://github.com/mahmoodhamdi/nawawi_40_hadith_app
- Source file: `assets/json/40-hadith-nawawi.json`
- Imported into Qalam Muslim as: `assets/data/nawawi_40_hadith_ar.json`
- License: MIT; the upstream copyright and permission notice are retained in `assets/licenses/NOTICE_NAWAWI_40_HADITH_MIT.txt`.
- Scope: the 42 entries' titles, Arabic hadith texts, narrator, collection, number, and original Sunnah.com reference URL. The lengthy explanatory descriptions and study notes are deliberately excluded from this import; they should be independently reviewed before being treated as religious instruction.

## Feature research and adaptation

The following MIT-licensed public repositories were reviewed as references for feature coverage. The new Qalam Muslim pages use the existing project's Theme, StorageService, navigation, and Arabic-first UI rather than copying entire applications or introducing their provider trees.

- https://github.com/safvan96/islamic-companion-app — fasting calendar, Hajj/Umrah checklists, daily good deeds, Sadaqah ideas, and Janazah learning.
- https://github.com/muhammadtalhasultan/Sirat-E-Mustaqeem — organization of Quran, supplication, Qibla, and tasbih features.
- https://github.com/mo7amedaliEbaid/islamic — five-pillars learning structure and Arabic/English Islamic feature organization.

Each upstream project retains its own copyright and license. No audio recordings, fonts, artwork, or third-party binaries from these references are bundled by this change.

## Religious-content handling

- Each imported Nawawi Hadith retains its individual source reference URL.
- The Hajj/Umrah area is an educational checklist, not a fatwa. Details may differ by type of nusuk and recognized juristic guidance.
- The funeral section is a remembrance and dua aid, not a substitute for local scholarly guidance.
- Checking off an item in the personal tracker does not imply that a deed has been accepted.
