# EyeTracking Practice

دو برنامهٔ انگلیسی برای آزمون و تمرین نگاه (تماس چشمی) با یک بستر پژوهشی مشترک:
اپ شرکت‌کننده (Participant App) و پنل پژوهشگر (Research Admin).

## اسناد

| مسیر | محتوا |
|---|---|
| `docs/design/EyeTracking-Product-Design-FA-v1.1.pdf` | سند طراحی محصول، نسخهٔ ۱٫۱ (۲۹ سپتامبر ۲۰۲۶)، با اعمال ۹ نظر بازبین |
| `docs/design/EyeTracking-Product-Design-FA-v1.1.html` | نسخهٔ قابل ویرایش همان سند؛ چاپ به PDF از مرورگر با اندازهٔ A4 |
| `docs/design/EyeTracking-Product-Design-FA-v1.0.pdf` | نسخهٔ قبلی سند طراحی |
| `docs/research/Brief-Face-Attention-Research-Proposal-v2.0-en.pdf` | پیشنهاد پژوهشی انگلیسی که برای بازبینی فرستاده شد |
| `docs/research/reviewer-comments-2026-09-28.md` | متن ۹ نظر بازبین با جملهٔ هایلایت‌شدهٔ هر کدام |

## وضعیت

گام ۱ برنامهٔ ساخت در حال اجراست: سرویس حساب، نقش‌ها، دعوت، برگهٔ اطلاعات و رضایت، پروفایل و فرم جمعیت‌شناختی آماده و آزمون‌شده است؛ صفحه‌های Flutter در حال تکمیل‌اند. وضعیت کوتاه در `docs/current-state.md` و یادداشت هر گام در `docs/features/`.
اتصال به سرویس پولی و آغاز پژوهش با شرکت‌کننده هنوز شروع نشده است. تصمیم‌های باز در صفحهٔ ۷ سند طراحی فهرست شده‌اند.

## ساختار مخزن

| مسیر | محتوا |
|---|---|
| `backend/` | سرویس Python / FastAPI برای حساب، جلسه و داده (`backend/README.md`) |
| `apps/participant/` | اپ شرکت‌کننده (Flutter) |
| `apps/admin/` | پنل پژوهشگر (Flutter) |
| `packages/core/` | بستهٔ مشترک Flutter: تم، کلاینت API، مدل‌ها |
| `docs/` | سند طراحی، پژوهش، وضعیت فعلی و یادداشت گام‌ها |

قواعد توسعه در `AGENTS.md` آمده است.
