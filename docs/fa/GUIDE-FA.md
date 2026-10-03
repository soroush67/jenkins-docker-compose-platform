<div dir="rtl">

# راهنمای کامل compose-cd

> **compose-cd** راهی است برای این‌که فایل‌های `docker-compose.yml` را از روی لپ‌تاپ خودتان، **از طریق Jenkins**، در repo مربوط به CD قرار دهید، بدون این‌که به آن repo دسترسی نوشتن داشته باشید.
>
> - 👩‍💻 **توسعه‌دهنده:** [بخش ۳](#۳-راهنمای-توسعهدهنده)
> - 🛠️ **ادمین:** [بخش ۴](#۴-راهنمای-ادمین)
> - 🧪 **محیط تست محلی (lab):** [بخش ۵](#۵-محیط-تست-محلی-lab)
> - ❓ **سؤالات متداول:** [بخش ۶](#۶-سؤالات-متداول)

---

## ۱. این سرویس چه کار می‌کند؟

در repo مربوط به CD، هر پوشه یک فایل `docker-compose.yml` دارد. مثلاً:

<div dir="ltr">

```
cd/
├── services/payment/docker-compose.yml
├── services/orders/docker-compose.yml
├── services/notification/docker-compose.yaml
└── infra/monitoring/compose.yaml
```

</div>

با compose-cd:

۱. در Jenkins، از یک **لیست کشویی** یکی از همین فایل‌ها را انتخاب می‌کنید.
۲. نسخه‌ی جدید فایل را از لپ‌تاپ **آپلود** می‌کنید.
۳. Jenkins فایل را **دقیقاً در همان مسیر** می‌گذارد، commit می‌کند و **git push** می‌کند.
۴. از آن به بعد، CD شما مثل همیشه از روی repo کارش را انجام می‌دهد.

هر وقت هم بخواهید، Jenkins فایل فعلی هر مسیر را از git می‌خواند و در **Console Output** نشان می‌دهد.

<div dir="ltr">

```
لپ‌تاپ  ──آپلود──►  Jenkins (cd/upload-compose)
                       ├─ clone تازه از repo
                       ├─ بررسی: مسیر انتخابی هنوز در repo هست؟
                       ├─ چاپ فایل در Console
                       ├─ جایگزینی فایل + commit  (نویسنده = شما)
                       └─ git push  ──►  repo CD  ──►  CD شما
```

</div>

---

## ۲. jobها و دسترسی‌ها

| job | چه کسی | کار |
|---|---|---|
| `cd/upload-compose` | توسعه‌دهنده | آپلود فایل و push در مسیر انتخاب‌شده |
| `cd/show-compose` | توسعه‌دهنده | نمایش فایل فعلی یک مسیر در Console |
| `cd-admin/refresh-paths` | ادمین (و خودکار) | به‌روز کردن لیست مسیرها از روی repo |

**توسعه‌دهنده:**
- فقط پوشه‌ی `cd` و دو job آن را می‌بیند.
- تنظیمات job، Workspace، credentialها، پوشه‌ی `cd-admin` و Manage Jenkins را نمی‌بیند.
- به repo دسترسی نوشتن ندارد. فقط کاربر bot جنکینز push می‌کند.
- **فقط** در مسیرهایی که از قبل در repo هستند می‌تواند فایل بگذارد. فایل یا پوشه‌ی جدید نمی‌تواند بسازد.

---

## ۳. راهنمای توسعه‌دهنده

### ۳-۱. آپلود فایل (قدم به قدم)

۱. آدرس Jenkins را باز کنید و با نام کاربری خودتان وارد شوید.
۲. پوشه‌ی **cd** را باز کنید و روی **upload-compose** کلیک کنید.
۳. در منوی سمت چپ روی **Build with Parameters** بزنید.
۴. فرم را پر کنید:

| فیلد | توضیح |
|---|---|
| **TARGET** | مسیر فایلی که می‌خواهید عوض شود، از لیست. مثلاً `services/payment/docker-compose.yml` |
| **COMPOSE_FILE** | فایل جدید را از لپ‌تاپ انتخاب کنید. اسم فایل روی لپ‌تاپ مهم نیست؛ همیشه در مسیر TARGET ذخیره می‌شود. |
| **CHANGE_NOTE** | توضیح کوتاه تغییر. این متن عنوان commit در git می‌شود. مثال: `bump payment-api to 1.5.0` |

۵. روی **Build** بزنید.
۶. در **Build History** روی build جدید و بعد روی **Console Output** کلیک کنید.

### ۳-۲. در Console چه می‌بینید؟

<div dir="ltr">

```
==================== upload ====================
repository  : https://gitlab.example.com/platform/cd.git  (branch main)
path        : services/payment/docker-compose.yml
uploaded by : dev1
change note : bump payment-api to 1.5.0
--------------- uploaded file ---------------
services:
  payment-api:
    image: registry.example.com/payment-api:1.5.0
    ...
================================================
 services/payment/docker-compose.yml | 2 +-
Pushed services/payment/docker-compose.yml to main as commit 3f2a9c1e...
https://gitlab.example.com/platform/cd/-/commit/3f2a9c1e...
Finished: SUCCESS
```

</div>

با لینک آخر، commit را مستقیم در GitLab می‌بینید. در GitLab، **نویسنده‌ی commit شما هستید** و پیام commit این‌طور است:

<div dir="ltr">

```
services/payment/docker-compose.yml: bump payment-api to 1.5.0

Uploaded-by: dev1
Jenkins-build: https://jenkins.example.com/job/cd/job/upload-compose/12/
```

</div>

### ۳-۳. دیدن فایل فعلی (show-compose)

۱. پوشه‌ی **cd** را باز کنید و job **show-compose** را انتخاب کنید.
۲. **Build with Parameters** را بزنید، TARGET را انتخاب کنید و **Build** را بزنید.
۳. در **Console Output** این را می‌بینید:

<div dir="ltr">

```
==================== services/payment/docker-compose.yml ====================
repository  : https://gitlab.example.com/platform/cd.git  (branch main)
last change : 3f2a9c1  2026-10-03 15:40:12 +0330  by dev1
services/payment/docker-compose.yml: bump payment-api to 1.5.0
Uploaded-by: dev1
---------------------------------------------------
services:
  payment-api:
    ...
```

</div>

این job فقط خواندنی است و هیچ چیزی را تغییر نمی‌دهد.

> 💡 **روش پیشنهادی برای تغییر:** اول show-compose را اجرا کنید و فایل فعلی را از Console کپی کنید. تغییرتان را روی همان بدهید و بعد آپلود کنید. این‌طوری چیزی را که کس دیگری قبلاً اضافه کرده، تصادفاً پاک نمی‌کنید.

### ۳-۴. معنی نتیجه‌ی build

| نتیجه | معنی |
|---|---|
| ✅ **SUCCESS** و `Pushed ... as commit ...` | فایل در git ثبت و push شد |
| ✅ **SUCCESS** و `identical ... nothing to commit` | فایلی که فرستادید با نسخه‌ی git فرقی نداشت؛ commitی ساخته نشد |
| ❌ **FAILURE** | هیچ چیزی در git تغییر نکرد؛ دلیلش در Console است (جدول پایین) |

### ۳-۵. خطاهای رایج

| پیغام در Console | معنی | راه‌حل |
|---|---|---|
| `No file was uploaded (COMPOSE_FILE is empty).` | فایلی انتخاب نشده یا فایل خالی است | دوباره بفرستید و فایل را انتخاب کنید |
| `'...' is not an existing compose file in ... any more` | این مسیر دیگر در repo نیست (مثلاً کسی پوشه را حذف کرده) و لیست هنوز به‌روز نشده | چند دقیقه صبر کنید تا لیست خودکار به‌روز شود، یا به ادمین بگویید `refresh-paths` را اجرا کند |
| `push rejected (attempt 1) - rebasing on the latest main` | هم‌زمان کس دیگری در repo push کرده بود | کاری لازم نیست؛ Jenkins خودش تغییر شما را روی آخرین نسخه می‌گذارد و دوباره push می‌کند |
| `push failed 3 times` یا خطای دسترسی در `git push` | Jenkins نتوانست push کند (مثلاً branch محافظت‌شده یا مشکل token) | به ادمین خبر دهید |
| `CONFLICT` هنگام rebase | کس دیگری **همین فایل** را هم‌زمان تغییر داده | show-compose را اجرا کنید، نسخه‌ی جدید را ببینید و تغییرتان را روی آن دوباره بفرستید |

### ۳-۶. نکته‌های مهم

- **فایل کامل بفرستید.** فایل آپلودی **کل** فایل قبلی را جایگزین می‌کند؛ ادغام (merge) نمی‌شود.
- **فقط مسیرهای موجود.** اگر برای یک سرویس جدید پوشه‌ی تازه لازم دارید، از ادمین بخواهید آن را در repo بسازد. بعد از به‌روز شدن لیست، از طریق Jenkins فایلش را عوض کنید.
- **بررسی خودکار و تأیید ندارد.** فایل مستقیم در branch اصلی push می‌شود و CD شما آن را برمی‌دارد. قبل از آپلود، روی لپ‌تاپ درستی فایل را با این دستور چک کنید (پایین).

<div dir="ltr">

```
docker compose -f docker-compose.yml config
```

</div>

- **رمز و secret ننویسید.** فایل در git ذخیره و در Console چاپ می‌شود.
- **برگرداندن نسخه‌ی قبلی:** نسخه‌ی قبلی فایل در Console Output buildهای قبلی (Build History) یا در تاریخچه‌ی GitLab هست. آن را ذخیره کنید و مثل یک آپلود معمولی بفرستید (مثلاً با CHANGE_NOTE `rollback to build #12`).

---

## ۴. راهنمای ادمین

### ۴-۱. اجزا

| جزء | توضیح |
|---|---|
| **repo پایپ‌لاین‌ها** (همین پروژه) | `jenkins/Jenkinsfile.upload`، `Jenkinsfile.show`، `Jenkinsfile.refresh`، `jobs.groovy`، `cdrepo.groovy` |
| **repo CD** | جایی که فایل‌های compose هستند و Jenkins در آن push می‌کند |
| **کاربر bot در GitLab** | تنها کاربری که از طرف Jenkins push می‌کند |
| **credential در Jenkins** | نام کاربری و token همان bot |

### ۴-۲. تنظیمات (متغیرهای سراسری Jenkins)

مسیر: Manage Jenkins ← System ← Global properties ← Environment variables

| متغیر | مثال | توضیح |
|---|---|---|
| `CD_REPO` | `https://gitlab.example.com/platform/cd.git` | آدرس repo CD |
| `CD_BRANCH` | `main` | branchی که از آن خوانده و در آن push می‌شود |
| `CD_GIT_CRED` | `gitlab-bot` | شناسه‌ی credential از نوع *Username with password*: نام کاربری bot و token |
| `CD_PIPELINE_REPO` | `https://gitlab.example.com/platform/compose-cd.git` | آدرس repo همین پروژه |
| `CD_PIPELINE_BRANCH` | `main` | |
| `CD_PATH_REGEX` | (اختیاری) `^services/.*(docker-)?compose\.ya?ml$` | کدام فایل‌ها در لیست بیایند (به سبک `grep -E`). اگر خالی باشد، همه‌ی `docker-compose.yml`، `docker-compose.yaml`، `compose.yml` و `compose.yaml`ها می‌آیند. با این متغیر می‌توانید مثلاً پوشه‌ی `infra/` را از دسترس توسعه‌دهنده‌ها بیرون بگذارید. |

### ۴-۳. نصب روی Jenkins واقعی

۱. **repo پایپ‌لاین‌ها:** این پروژه را در GitLab سازمان push کنید (مثلاً `platform/compose-cd`).
۲. **کاربر bot:** در GitLab یک کاربر بسازید (مثلاً `jenkins-bot`) و برایش یک Personal Access Token با scopeهای `read_repository` و `write_repository` بگیرید. این کاربر روی repo پایپ‌لاین‌ها دسترسی خواندن و روی repo CD دسترسی push به `CD_BRANCH` لازم دارد. اگر branch محافظت‌شده است، در *Protected branches* به این کاربر اجازه‌ی push بدهید.
۳. **پلاگین‌ها:** فهرست کامل در `lab/jenkins/plugins.txt` است (مهم‌ترین‌ها: `role-strategy`، `file-parameters`، `job-dsl`، `lockable-resources`، `credentials-binding`، `git`). پلاگین‌ها را به‌روز نگه دارید.
۴. **agent:** یک agent با label **`cd`** که `git` روی آن نصب باشد.
۵. **credential:** Manage Jenkins ← Credentials ← System ← Global ← *Username with password* با ID مثلاً `gitlab-bot`.
۶. **متغیرهای سراسری:** مطابق [بخش ۴-۲](#۴-۲-تنظیمات-متغیرهای-سراسری-jenkins).
۷. **امنیت Job DSL:** Manage Jenkins ← Security ← *Enable script security for Job DSL scripts* را خاموش کنید، یا بعد از اولین اجرای refresh اسکریپت را در *In-process Script Approval* تأیید کنید.
۸. **نقش‌ها** (پلاگین Role-based Authorization Strategy):
   - نقش سراسری برای همه‌ی کاربران وارد شده: `Overall/Read`
   - نقش Item با نام `cd-user` و الگوی `cd(/.*)?`، با دسترسی‌های `Job/Read` و `Job/Build`
   - توسعه‌دهنده‌ها (یا گروه LDAP آن‌ها) را در **Assign Roles** به `cd-user` اضافه کنید.
۹. **job ادمین:** پوشه‌ی `cd-admin` بسازید و داخلش یک Pipeline با نام `refresh-paths`: *Pipeline script from SCM*، repo پایپ‌لاین‌ها، Script Path: `jenkins/Jenkinsfile.refresh`. فقط ادمین به این پوشه دسترسی داشته باشد.
۱۰. `refresh-paths` را یک بار اجرا کنید. پوشه‌ی `cd` و دو job آن ساخته می‌شوند و polling خودکار هم فعال می‌شود.
۱۱. با یک کاربر توسعه‌دهنده‌ی آزمایشی وارد شوید و بررسی کنید که فقط پوشه‌ی `cd` را می‌بیند.

> ⚠️ هرگز `Job/Configure`، `Job/Workspace` یا Credentials را به `cd-user` ندهید. با Configure هر کسی می‌تواند Jenkinsfile را عوض کند و به token برسد.

### ۴-۴. به‌روز شدن لیست مسیرها

- `refresh-paths` هر **۵ دقیقه** repo CD را چک می‌کند. اگر تغییری بوده باشد (پوشه یا فایل compose اضافه یا حذف شده)، لیست کشویی هر دو job را دوباره می‌سازد.
- برای اعمال فوری، خودتان **Build Now** را بزنید.
- حتی اگر لیست قدیمی باشد، **خطری ندارد**: هر آپلود قبل از نوشتن، مسیر را روی یک clone تازه دوباره چک می‌کند. اگر مسیر دیگر نباشد، build با خطا تمام می‌شود و هیچ فایلی ساخته نمی‌شود.

**اضافه کردن یک سرویس جدید:** پوشه و یک فایل compose اولیه را مستقیم در repo CD commit کنید (مثلاً `services/billing/docker-compose.yml`). بعد از refresh، این مسیر در لیست ظاهر می‌شود و توسعه‌دهنده‌ها می‌توانند فایلش را عوض کنند.

### ۴-۵. پیگیری (audit)

| کجا | چه اطلاعاتی |
|---|---|
| **GitLab** – تاریخچه‌ی repo CD | هر آپلود یک commit است: author = کاربر Jenkins، committer = Jenkins، و در پیام commit: `Uploaded-by` و `Jenkins-build` (لینک build) |
| **Jenkins** – Build History در `upload-compose` | توضیح هر build: «مسیر – by کاربر @ commit»، و Console کامل شامل خود فایل |

### ۴-۶. تغییر token

۱. در GitLab برای bot یک token جدید بسازید.
۲. credential `gitlab-bot` را در Jenkins به‌روز کنید.
۳. یک show-compose اجرا کنید تا مطمئن شوید کار می‌کند.
۴. token قدیمی را در GitLab revoke کنید.

### ۴-۷. تغییر خود پایپ‌لاین‌ها

فایل‌های `jenkins/*` را در repo پایپ‌لاین‌ها تغییر دهید و push کنید. buildهای بعدی نسخه‌ی جدید را خودشان می‌خوانند. اگر **پارامترهای** jobها را عوض کرده‌اید (فایل `jenkins/jobs.groovy`)، `refresh-paths` را اجرا کنید.

---

## ۵. محیط تست محلی (lab)

lab همه‌چیز را روی یک ماشین بالا می‌آورد: **GitLab CE 17.10.5**، که یک repo CD نمونه به اسم `platform/cd` دارد، و **Jenkins** با همه‌ی تنظیمات.

<div dir="ltr">

```
cd ~/infra/docker-compose-platform

lab/up.sh            # بالا آوردن؛ در پایان نام‌های کاربری و رمزها را چاپ می‌کند
tests/e2e.sh         # تست کامل از طریق API جنکینز (۴۵ بررسی)؛ چند بار هم قابل اجراست
lab/down.sh          # خاموش کردن (داده‌ها می‌مانند)
lab/down.sh --wipe   # خاموش کردن و پاک کردن همه‌ی داده‌ها و رمزها
```

</div>

| چه چیزی | آدرس | ورود |
|---|---|---|
| Jenkins | http://localhost:8090 | کاربران `admin`، `dev1`، `dev2`؛ رمزها در `lab/secrets/jenkins.env` |
| GitLab | http://localhost:8929 | کاربر `root`؛ رمز در `lab/.env` |
| repo CD | http://localhost:8929/platform/cd | |

<div dir="ltr">

```
cat lab/secrets/jenkins.env lab/.env      # دیدن رمزها
```

</div>

**یک دور تست دستی:**

۱. یک فایل روی لپ‌تاپ بسازید، مثلاً `payment.yml`:

<div dir="ltr">

```yaml
services:
  payment-api:
    image: registry.example.com/payment-api:1.5.0
    ports:
      - "8081:8080"
```

</div>

۲. در Jenkins با `dev1` وارد شوید. پوشه‌ی **cd** را باز کنید، **upload-compose** را انتخاب کنید و **Build with Parameters** را بزنید.
   - TARGET: `services/payment/docker-compose.yml`
   - COMPOSE_FILE: فایل `payment.yml`
   - CHANGE_NOTE: `bump to 1.5.0`
   - **Build** را بزنید.
۳. در Console Output، فایل و لینک commit را می‌بینید و build باید SUCCESS شود.
۴. در GitLab با `root` وارد شوید و repo `platform/cd` را باز کنید. در بخش Commits، commit شما با نویسنده‌ی `dev1` آمده است. فایل `services/payment/docker-compose.yml` هم الان همان محتوای آپلودی شماست.
۵. با `dev1` job **show-compose** را برای همان مسیر اجرا کنید. فایل جدید در Console نمایش داده می‌شود.
۶. (اختیاری) در GitLab با `root` یک پوشه‌ی جدید بسازید، مثلاً `services/billing/docker-compose.yml`. بعد با `admin` job **cd-admin/refresh-paths** را اجرا کنید، یا ۵ دقیقه صبر کنید. مسیر جدید باید در لیست TARGET ظاهر شود.

> lab فقط برای تست است و رمزهایش در فایل‌های محلی‌اند (commit نمی‌شوند). اگر `jenkins/` را تغییر دادید، دوباره `lab/up.sh` را اجرا کنید تا به GitLab داخل lab push شود.

---

## ۶. سؤالات متداول

**می‌توانم فایل را در مسیر جدیدی بگذارم که هنوز در repo نیست؟**
خیر، عمداً. فقط مسیرهای موجود در لیست هستند. پوشه‌ی جدید را ادمین (یا هر کسی که دسترسی repo دارد) می‌سازد.

**اگر دو نفر هم‌زمان آپلود کنند چه می‌شود؟**
آپلودها پشت سر هم انجام می‌شوند (قفل روی repo). اگر فایل‌ها متفاوت باشند، هر دو ثبت می‌شوند. اگر هر دو نفر یک فایل را فرستاده باشند، آخری برنده است؛ هر دو commit در تاریخچه می‌مانند.

**اگر کسی هم‌زمان مستقیم در repo push کند؟**
مشکلی نیست. Jenkins تغییر شما را روی آخرین نسخه rebase می‌کند و دوباره push می‌کند. تغییر آن شخص هم حفظ می‌شود.

**فایل‌های دیگر مثل `.env` یا config را هم می‌توانم بفرستم؟**
فعلاً فقط فایل‌های compose. اگر لازم شد، با تغییر `CD_PATH_REGEX` و کمی تغییر در پایپ‌لاین قابل اضافه شدن است.

**قبل از push، کسی فایل را بررسی یا تأیید می‌کند؟**
خیر؛ طبق طراحی فعلی فایل مستقیم push می‌شود. اگر بعداً لازم شد، می‌شود مرحله‌ی تأیید یا بررسی خودکار اضافه کرد، یا Jenkins را به‌جای push مستقیم به ساختن Merge Request تغییر داد.

</div>
