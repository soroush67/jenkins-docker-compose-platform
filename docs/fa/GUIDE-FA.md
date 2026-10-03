<div dir="rtl">

# راهنمای کامل compose-paas

> **compose-paas** یعنی Jenkins به‌عنوان یک «پلتفرم سرویس» برای استقرار (deploy) برنامه‌هایی که با docker-compose اجرا می‌شوند.
>
> این راهنما سه بخش اصلی دارد؛ فقط بخشی را بخوانید که به نقش شما مربوط است:
>
> - 👩‍💻 **توسعه‌دهنده** (کسی که فایل docker-compose.yml را می‌فرستد): [بخش ۳](#۳-راهنمای-توسعهدهنده)
> - ✅ **تأییدکننده** (کسی که deploy را تأیید یا رد می‌کند): [بخش ۴](#۴-راهنمای-تأییدکننده)
> - 🛠️ **ادمین پلتفرم** (کسی که سرویس‌ها، کاربران و سرورها را تعریف می‌کند): [بخش ۵](#۵-راهنمای-ادمین-پلتفرم)
>
> محیط تست محلی (lab): [بخش ۶](#۶-محیط-تست-محلی-lab) — سؤالات متداول: [بخش ۷](#۷-سؤالات-متداول)

---

## ۱. این سرویس چیست و چه مشکلی را حل می‌کند؟

قبلاً برای استقرار یک سرویس، توسعه‌دهنده باید به repoهای زیرساختی دسترسی نوشتن داشت، یا روی سرور SSH می‌زد و خودش `docker compose up` اجرا می‌کرد. یعنی دسترسی زیاد، بدون تأیید، و بدون سابقه‌ی مشخص.

با compose-paas:

- توسعه‌دهنده **فقط** در Jenkins یک سرویس را انتخاب می‌کند و فایل `docker-compose.yml` خودش را **آپلود** می‌کند.
- یک **تأییدکننده** فایل را می‌بیند و تأیید یا رد می‌کند.
- بعد از تأیید، **خود Jenkins** فایل را در **مسیر git تعریف‌شده** برای آن سرویس commit می‌کند و همان نسخه را روی **سرور تعریف‌شده** deploy می‌کند.
- هر وقت لازم باشد، با یک job دیگر، Jenkins فایل فعلی را از git می‌خواند و در **Console Output** نشان می‌دهد.

توسعه‌دهنده **هیچ‌وقت** به repoهای استقرار دسترسی نوشتن ندارد، به سرورها SSH نمی‌زند، و تنظیمات jobهای Jenkins را نمی‌بیند و نمی‌تواند تغییر دهد.

### جریان کار در یک نگاه

<div dir="ltr">

```
توسعه‌دهنده                     Jenkins                          تأییدکننده
─────────────                   ───────                          ──────────
انتخاب سرویس +
آپلود docker-compose.yml  ──►  ۱. خواندن services.yaml
                                   (مسیر git، سرور، approverها)
                                ۲. چاپ فایل در Console
                                ۳. منتظر تأیید  ─────────────────►  بررسی فایل در Console
                                                                   Approve  یا  Abort
                                ◄──────────────────────────────────
                                ۴. commit + push در git
                                   (با نام درخواست‌دهنده و تأییدکننده)
                                ۵. deploy روی سرور با Ansible
                                   docker compose up -d --wait
                                ۶. SUCCESS / FAILURE
```

</div>

---

## ۲. نقش‌ها و دسترسی‌ها

| نقش | در Jenkins چه می‌بیند | چه کاری می‌تواند بکند | چه کاری نمی‌تواند بکند |
|---|---|---|---|
| **توسعه‌دهنده** | فقط پوشه‌ی `paas` و دو job داخل آن | درخواست deploy، دیدن فایل فعلی، دیدن Console | تأیید درخواست خودش، تغییر تنظیمات job، دیدن Workspace یا credentialها، دیدن پوشه‌ی `paas-admin`، Manage Jenkins |
| **تأییدکننده** | مثل توسعه‌دهنده | علاوه بر کارهای توسعه‌دهنده: تأیید یا رد درخواست **دیگران** برای سرویس‌هایی که در فهرست approverهایشان است | تأیید درخواست **خودش** |
| **ادمین پلتفرم** | همه‌چیز | تعریف سرویس‌ها، کاربران، سرورها، credentialها | — (اما او هم نمی‌تواند درخواست خودش را تأیید کند) |

> ⚠️ قانون «هیچ‌کس درخواست خودش را تأیید نمی‌کند» برای **همه** اجرا می‌شود، حتی ادمین. اگر ادمین درخواستی بدهد و خودش آن را تأیید کند، build با خطا تمام می‌شود و هیچ چیزی commit یا deploy نمی‌شود.

### jobها

| job | برای چه کسی | کار |
|---|---|---|
| `paas/deploy-compose` | توسعه‌دهنده | آپلود فایل ← تأیید ← commit در git ← deploy |
| `paas/show-compose` | توسعه‌دهنده | خواندن فایل فعلی از git و نمایش آن در Console |
| `paas-admin/sync-registry` | فقط ادمین | خواندن `services.yaml` و ساختن یا به‌روز کردن دو job بالا |

---

## ۳. راهنمای توسعه‌دهنده

### ۳-۱. ورود

۱. آدرس Jenkins را در مرورگر باز کنید (در محیط تست: `http://localhost:8090`).
۲. با نام کاربری و رمزی که ادمین به شما داده وارد شوید.
۳. در صفحه‌ی اول فقط پوشه‌ی **paas** را می‌بینید. روی آن کلیک کنید.

### ۳-۲. فرستادن یک deploy (قدم به قدم)

۱. روی job **`deploy-compose`** کلیک کنید.
۲. در منوی سمت چپ روی **Build with Parameters** بزنید.
۳. فرم را پر کنید:

| فیلد | توضیح |
|---|---|
| **SERVICE** | نام سرویس از فهرست. فقط سرویس‌هایی که ادمین تعریف کرده در فهرست هستند. اگر سرویس شما نیست، از ادمین بخواهید اضافه‌اش کند. |
| **COMPOSE_FILE** | فایل `docker-compose.yml` خود را با دکمه‌ی انتخاب فایل آپلود کنید. نام فایل روی کامپیوتر شما مهم نیست؛ همیشه با نام و مسیری که برای سرویس تعریف شده در git ذخیره می‌شود. |
| **CHANGE_NOTE** | توضیح کوتاه: چه چیزی تغییر کرده و چرا. این متن در پیام commit در git ثبت می‌شود. مثال: `upgrade nginx to 1.27`. |

۴. روی **Build** بزنید.
۵. یک build جدید در **Build History** (پایین سمت چپ) ظاهر می‌شود. روی شماره‌ی آن و بعد روی **Console Output** کلیک کنید.

### ۳-۳. بعد از فرستادن چه اتفاقی می‌افتد؟

در Console Output، اول خلاصه‌ی درخواست شما و **محتوای کامل فایلی که آپلود کرده‌اید** چاپ می‌شود:

<div dir="ltr">

```
==================== deploy request ====================
service      : hello-web
requested by : dev1
change note  : upgrade nginx
git target   : http://.../hello-web-deploy.git  (branch main)  deploy/docker-compose.yml
deploy to    : app-server-01:/opt/apps/hello-web
approvers    : approver1, admin
------------------ uploaded docker-compose.yml ------------------
services:
  web:
    image: nginx:1.27-alpine
    ...
==========================================================
Deploy hello-web to app-server-01 (requested by dev1)? ...
Approve & deploy or Abort
```

</div>

**دقت کنید که فایل درست را فرستاده‌اید.** از اینجا به بعد build منتظر تأیید می‌ماند.

- به یکی از افرادی که در خط `approvers` آمده‌اند خبر دهید که درخواست شما منتظر است. لینک build را برایشان بفرستید.
- شما **نمی‌توانید** درخواست خودتان را تأیید کنید. اگر روی `Approve & deploy` بزنید، پیغام «You need to be ... to submit this» را می‌بینید.
- اگر پشیمان شدید یا فایل اشتباه فرستادید، build را با دکمه‌ی **✕ (توقف)** کنار build متوقف کنید و یک درخواست جدید بفرستید.
- اگر تا **۲۴ ساعت** کسی تأیید نکند، درخواست خودبه‌خود لغو می‌شود (ABORTED).

بعد از تأیید، در ادامه‌ی همان Console می‌بینید:

<div dir="ltr">

```
Approved by approver1
Committed and pushed:
  3f2a9c1e...
  author dev1, ...
TASK [docker compose up] ...
...
Deployed hello-web @ 3f2a9c1e04 to app-server-01:/opt/apps/hello-web
Finished: SUCCESS
```

</div>

### ۳-۴. معنی وضعیت‌های build

| وضعیت | معنی | چه کار کنید |
|---|---|---|
| ⏸️ آبی چشمک‌زن / «Paused for Input» | منتظر تأیید | به approver خبر دهید |
| ✅ **SUCCESS** | فایل در git commit شد و روی سرور بالا آمد | — |
| ⚪ **ABORTED** | درخواست رد شد، یا لغو شد، یا ۲۴ ساعت منتظر ماند | هیچ چیزی در git یا روی سرور عوض نشده. در صورت نیاز دوباره بفرستید |
| ❌ **FAILURE** | خطا رخ داد | Console را بخوانید؛ جدول خطاها در [بخش ۳-۷](#۳-۷-خطاهای-رایج-و-معنی-آنها) |
| 🟡 **UNSTABLE** (فقط در show-compose) | برای این سرویس هنوز هیچ فایلی deploy نشده | — |

> ⚠️ **ترتیب کار «اول commit، بعد deploy» است.** اگر فایل تأیید شود و commit شود ولی deploy روی سرور خطا بدهد (مثلاً کانتینر بالا نیاید)، **فایل جدید در git می‌ماند** و build قرمز (FAILURE) می‌شود. مشکل را درست کنید و نسخه‌ی اصلاح‌شده را دوباره بفرستید، یا نسخه‌ی قبلی را بفرستید (بخش [۳-۸](#۳-۸-برگرداندن-نسخهی-قبلی-rollback)).

### ۳-۵. دیدن فایل فعلی یک سرویس (show-compose)

۱. وارد پوشه‌ی **paas** شوید و job **`show-compose`** را باز کنید.
۲. **Build with Parameters** ← سرویس را انتخاب کنید ← **Build**.
۳. روی build جدید و بعد روی **Console Output** کلیک کنید.

Jenkins فایل را **همان لحظه** از git می‌خواند و نشان می‌دهد:

<div dir="ltr">

```
==================== hello-web ====================
repo        : http://.../hello-web-deploy.git
branch/path : main:deploy/docker-compose.yml
deployed to : app-server-01:/opt/apps/hello-web
last change : 3f2a9c1  2026-10-03 13:58:47 +0000  by dev1
deploy(hello-web): upgrade nginx

Requested-by: dev1
Approved-by: approver1
Jenkins-build: http://jenkins/job/paas/job/deploy-compose/12/
--------------------- docker-compose.yml ---------------------
services:
  web:
    ...
==============================================================
```

</div>

این job **فقط خواندنی** است، به تأیید نیاز ندارد و هیچ چیزی را تغییر نمی‌دهد. هر چند بار خواستید اجرایش کنید.

> 💡 بهترین روش برای تغییر یک سرویس: اول show-compose را اجرا کنید، فایل فعلی را از Console کپی کنید، تغییرتان را بدهید، و همان را با deploy-compose بفرستید. این‌طوری چیزی را که قبلاً بوده تصادفاً پاک نمی‌کنید.

### ۳-۶. نکته‌های مهم در نوشتن docker-compose.yml

| نکته | توضیح |
|---|---|
| **فقط یک فایل** | فقط `docker-compose.yml` منتقل می‌شود. فایل‌های کنار آن (`.env`، `nginx.conf`، اسکریپت‌ها و ...) **منتقل نمی‌شوند**. bind mount نسبی مثل `./nginx.conf:/etc/nginx/nginx.conf` روی سرور پیدا نمی‌شود. از imageهایی استفاده کنید که تنظیماتشان داخل خود image است، یا با ادمین هماهنگ کنید. |
| **فایل کامل بفرستید** | فایل جدید **جایگزین کامل** فایل قبلی می‌شود. هر سرویسی که از فایل حذف کنید، روی سرور **حذف می‌شود** (`--remove-orphans`). |
| **نسخه‌ی image را ثابت کنید** | به جای `nginx:latest` بنویسید `nginx:1.27-alpine`. با `latest` معلوم نیست چه نسخه‌ای اجرا می‌شود و برگشت به نسخه‌ی قبلی ممکن نیست. |
| **healthcheck بگذارید** | deploy با `--wait` اجرا می‌شود: Jenkins تا ۱۸۰ ثانیه صبر می‌کند تا همه‌ی کانتینرها **running** (و اگر healthcheck دارند **healthy**) شوند. اگر کانتینری crash کند یا healthy نشود، build با **FAILURE** تمام می‌شود. با healthcheck، Jenkins واقعاً می‌فهمد برنامه‌ی شما سالم بالا آمده یا نه. |
| **پورت‌ها** | پورتی که منتشر می‌کنید (`ports:`) نباید روی آن سرور در اختیار سرویس دیگری باشد. پورت‌های مجاز را از ادمین بپرسید. |
| **نام پروژه** | نام پروژه‌ی compose همیشه **نام سرویس** است (مثلاً `hello-web`)؛ `name:` داخل فایل را نگذارید. volumeهای نام‌دار هم با این پیشوند ساخته می‌شوند (`hello-web_data`) و در deployهای بعدی **حفظ می‌شوند**. |
| **رمز و secret** | رمز عبور را مستقیم در فایل ننویسید: فایل در git ذخیره می‌شود و در Console چاپ می‌شود و همه‌ی کسانی که به آن دسترسی دارند آن را می‌بینند. |
| **درستی فایل** | فایل قبل از تأیید به‌صورت خودکار بررسی **نمی‌شود**؛ تنها کنترل، نگاه تأییدکننده است. قبل از فرستادن روی کامپیوتر خودتان `docker compose -f docker-compose.yml config` را اجرا کنید تا مطمئن شوید فایل معتبر است. |

### ۳-۷. خطاهای رایج و معنی آن‌ها

| پیغام در Console | معنی | راه‌حل |
|---|---|---|
| `No docker-compose.yml was uploaded (COMPOSE_FILE is empty).` | فایل انتخاب نشده یا خالی بوده | دوباره بفرستید و فایل را انتخاب کنید |
| `Service 'x' is not in services.yaml (any more)` | سرویس از فهرست ادمین حذف شده ولی هنوز در dropdown هست | به ادمین خبر دهید تا `sync-registry` را اجرا کند |
| `No approver other than <شما> is configured for <سرویس>` | تنها approver این سرویس خود شما هستید و کس دیگری نیست که تأیید کند | از ادمین بخواهید approver دیگری اضافه کند |
| `<نام> requested this deploy and cannot approve it.` | کسی (معمولاً ادمین) درخواست خودش را تأیید کرده | کس دیگری باید تأیید کند؛ درخواست را دوباره بفرستید |
| `You need to be ... to submit this` (موقع زدن Approve) | شما اجازه‌ی تأیید این درخواست را ندارید | به یکی از approverهای نام‌برده خبر دهید |
| `Timeout has been exceeded` | ۲۴ ساعت کسی تأیید نکرد | دوباره بفرستید |
| در مرحله‌ی `docker compose up`: `container ... exited` یا `is unhealthy` یا `dependency failed` | کانتینر شما بالا نیامد یا سالم نشد | مشکل فایل یا image را درست کنید. توجه: فایل در git commit شده است ([۳-۴](#۳-۴-معنی-وضعیتهای-build)) |
| در مرحله‌ی `docker compose up`: `port is already allocated` | پورتی که منتشر کرده‌اید روی سرور اشغال است | پورت دیگری بگذارید (با ادمین هماهنگ کنید) |
| `pull access denied` / `manifest unknown` | نام یا tag image اشتباه است، یا registry در دسترس نیست | نام image را بررسی کنید |
| `UNREACHABLE` در Ansible | Jenkins به سرور مقصد وصل نمی‌شود | به ادمین خبر دهید (مشکل شبکه، SSH یا سرور) |
| `git push` rejected | مشکل دسترسی bot به repo یا branch محافظت‌شده | به ادمین خبر دهید |

### ۳-۸. برگرداندن نسخه‌ی قبلی (rollback)

دکمه‌ی جداگانه‌ای برای rollback وجود ندارد. راه درست:

۱. نسخه‌ی قبلی فایل را پیدا کنید: در Console Output یک deploy موفق قبلی (Build History همان job)، فایل کامل چاپ شده است. از آنجا کپی کنید.
۲. آن را در یک فایل `docker-compose.yml` ذخیره کنید.
۳. مثل یک deploy معمولی بفرستید و در CHANGE_NOTE بنویسید `rollback to build #N`.

این‌طوری rollback هم مثل هر تغییر دیگری تأیید می‌شود و در git ثبت می‌شود.

### ۳-۹. چیزهایی که عمداً نمی‌توانید انجام دهید

- انتخاب repo، مسیر git یا سرور مقصد (این‌ها را ادمین برای هر سرویس تعریف می‌کند)
- تغییر تنظیمات jobها یا دیدن Workspace یا credentialهای Jenkins
- تأیید درخواست خودتان
- اجرای دستور دلخواه روی سرور (فقط `docker compose up` اجرا می‌شود)

---

## ۴. راهنمای تأییدکننده

تأییدکننده **تنها کنترل** قبل از deploy است. هیچ بررسی خودکاری روی فایل انجام نمی‌شود، پس دقت شما اهمیت دارد.

### ۴-۱. پیدا کردن درخواست‌های منتظر

- توسعه‌دهنده معمولاً لینک build را برایتان می‌فرستد.
- یا: پوشه‌ی **paas** ← **deploy-compose** ← در Build History، buildهایی که در حال اجرا هستند (آیکن چشمک‌زن) منتظر تأییدند. در Stage View، مرحله‌ی **Approval** به‌صورت «paused» دیده می‌شود.

### ۴-۲. بررسی و تصمیم

۱. build را باز کنید و به **Console Output** بروید.
۲. بخش `deploy request` را بخوانید: سرویس، درخواست‌دهنده، توضیح تغییر، سرور مقصد و **فایل کامل**.
۳. اگر لازم است نسخه‌ی فعلی را ببینید و مقایسه کنید، `show-compose` را برای همان سرویس اجرا کنید.
۴. در پایین Console:
   - **Approve & deploy** ← فایل commit و deploy می‌شود.
   - **Abort** ← درخواست رد می‌شود و **هیچ چیزی** در git یا روی سرور تغییر نمی‌کند.

(همین دکمه‌ها از منوی سمت چپ build با نام **Paused for Input** هم در دسترس‌اند.)

### ۴-۳. چک‌لیست پیشنهادی قبل از تأیید

- [ ] سرویس و سرور مقصد همان چیزی است که انتظار دارید؟
- [ ] نسخه‌ی imageها ثابت است (`latest` نیست)؟
- [ ] `privileged: true`، `network_mode: host`، `pid: host` یا `cap_add` ندارد (مگر عمداً)؟
- [ ] مسیرهای حساس سرور را mount نکرده؟ (`/`، `/etc`، `/var/run/docker.sock`، ...)
- [ ] رمز یا secret داخل فایل نیست؟
- [ ] پورت‌ها با بقیه‌ی سرویس‌های آن سرور تداخل ندارند؟
- [ ] سرویسی که در نسخه‌ی قبلی بوده تصادفاً حذف نشده؟ (حذف از فایل = حذف از سرور)

### ۴-۴. محدودیت‌ها

- فقط کسانی که نامشان در `approvers` همان سرویس آمده می‌توانند تأیید کنند.
- درخواست **خودتان** را نمی‌توانید تأیید کنید؛ یک approver دیگر باید این کار را بکند.
- در git، پیام هر commit شامل `Approved-by: <نام شما>` است. تأیید شما ثبت و قابل پیگیری است.

---

## ۵. راهنمای ادمین پلتفرم

### ۵-۱. اجزای سیستم

| جزء | کجاست | چه کسی تغییرش می‌دهد |
|---|---|---|
| **repo پایپ‌لاین‌ها** (همین پروژه: `jenkins/`، `ansible/`) | GitLab، مثلاً `platform/compose-paas` | فقط ادمین |
| **repo تنظیمات** (`services.yaml`) | GitLab، مثلاً `platform/paas-config` | فقط ادمین |
| **repoهای استقرار هر سرویس** (جایی که docker-compose.yml commit می‌شود) | GitLab | فقط bot جنکینز push می‌کند. توسعه‌دهنده‌ها حداکثر دسترسی خواندن دارند |
| **credential git** (`PAAS_GIT_CRED`) | Jenkins | ادمین |
| **کلید SSH deploy** (`PAAS_SSH_CRED`) | Jenkins | ادمین |

### ۵-۲. تعریف، تغییر یا حذف یک سرویس

همه‌چیز در فایل `services.yaml` در repo تنظیمات است:

<div dir="ltr">

```yaml
defaults:
  branch: main
  approvers: [team-lead, platform-admin]     # شناسه‌ی کاربران Jenkins

services:
  hello-web:
    description: "Static hello page"
    repo: https://gitlab.example.com/platform/hello-web-deploy.git
    path: deploy/docker-compose.yml
    target_host: app-server-01.example.com
    deploy_dir: /opt/apps/hello-web
    approvers: [team-lead]                   # اختیاری؛ جایگزین defaults
```

</div>

| کلید | اجباری | توضیح |
|---|---|---|
| نام سرویس (مثلاً `hello-web`) | ✅ | فقط حروف کوچک انگلیسی، عدد، `-` و `_`، و با حرف یا عدد شروع شود. **همین نام، نام پروژه‌ی compose روی سرور است** — بعداً عوضش نکنید، وگرنه سرویس جدیدی کنار قبلی ساخته می‌شود. |
| `description` | — | در توضیح job نمایش داده می‌شود |
| `repo` | ✅ | آدرس HTTP(S) repo استقرار. bot باید روی آن دسترسی push داشته باشد |
| `branch` | — | پیش‌فرض `main` |
| `path` | ✅ | مسیر فایل داخل repo؛ نسبی و بدون `..` |
| `target_host` | ✅ | نام یا IP سروری که Jenkins با SSH به آن وصل می‌شود |
| `deploy_dir` | ✅ | مسیر مطلق روی سرور |
| `approvers` | ✅ (اینجا یا در `defaults`) | فهرست شناسه‌ی کاربران Jenkins که می‌توانند تأیید کنند |

**بعد از هر تغییر:**

۱. تغییر را در repo تنظیمات commit و push کنید.
۲. در Jenkins: **paas-admin** ← **sync-registry** ← **Build Now**.
۳. Console را ببینید: فهرست سرویس‌ها چاپ می‌شود. اگر یکی از مقادیر اشتباه باشد، job با پیغام دقیق خطا متوقف می‌شود و jobهای توسعه‌دهنده دست نمی‌خورند.

> 💡 حتی اگر `sync-registry` را فراموش کنید، هر build همیشه `services.yaml` را **همان لحظه** از git می‌خواند. پس تغییر مسیر، سرور یا approverها فوراً اعمال می‌شود. `sync-registry` فقط برای به‌روز کردن **فهرست کشویی** سرویس‌ها لازم است (اضافه یا حذف سرویس).

**حذف یک سرویس:** حذف آن از `services.yaml` فقط جلوی deployهای بعدی را می‌گیرد؛ کانتینرهای در حال اجرا روی سرور **حذف نمی‌شوند**. برای خاموش کردن واقعی، روی سرور در `deploy_dir` دستور `docker compose -p <نام> down` را اجرا کنید.

### ۵-۳. آماده کردن یک سرور مقصد جدید

روی هر سروری که در `target_host` می‌آید:

<div dir="ltr">

```bash
# ۱. کاربر deploy در گروه docker
sudo useradd -m -s /bin/bash -G docker deploy

# ۲. کلید عمومی SSH جنکینز (جفت کلید PAAS_SSH_CRED)
sudo install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
echo 'ssh-ed25519 AAAA... jenkins-deploy' | sudo tee /home/deploy/.ssh/authorized_keys
sudo chown deploy:deploy /home/deploy/.ssh/authorized_keys && sudo chmod 600 /home/deploy/.ssh/authorized_keys

# ۳. پوشه‌ی برنامه‌ها، قابل نوشتن برای deploy
sudo install -d -o deploy -g docker /opt/apps

# ۴. پیش‌نیازها: docker، docker compose (plugin یا docker-compose)، python3 (برای Ansible)
docker compose version && python3 --version
```

</div>

بعد از روی agent جنکینز تست کنید:

<div dir="ltr">

```bash
ssh -i <کلید> deploy@app-server-01 'docker ps'
```

</div>

> ⚠️ عضو گروه `docker` بودن عملاً معادل دسترسی root روی آن سرور است. این کاربر و کلید را فقط Jenkins باید داشته باشد.

**host key:** در lab بررسی host key خاموش است. در محیط واقعی، کلید هر سرور را در `~/.ssh/known_hosts` کاربر agent جنکینز اضافه کنید (`ssh-keyscan app-server-01 >> ~/.ssh/known_hosts`) و متغیر سراسری `PAAS_HOST_KEY_CHECKING=True` را تنظیم کنید.

### ۵-۴. آماده کردن repo استقرار یک سرویس

۱. در GitLab یک repo بسازید (مثلاً `platform/hello-web-deploy`) با حداقل یک commit (مثلاً README).
۲. کاربر bot جنکینز را **Maintainer** (یا Developer با اجازه‌ی push روی branch) کنید.
۳. به توسعه‌دهنده‌ها حداکثر دسترسی **Reporter** (فقط خواندن) بدهید، یا هیچ دسترسی‌ای ندهید. هدف این است که فقط از طریق Jenkins تغییر کند.
۴. اگر branch محافظت‌شده است، اجازه‌ی push را به bot بدهید.

### ۵-۵. کاربران و نقش‌ها در Jenkins

دسترسی‌ها با پلاگین **Role-based Authorization Strategy** تعریف شده‌اند:

| نقش | نوع | دسترسی‌ها |
|---|---|---|
| `admin` | Global | Overall/Administer |
| `authenticated-read` | Global (برای همه‌ی کاربران وارد شده) | Overall/Read |
| `paas-user` | Item، الگوی `paas(/.*)?` | Job/Read، Job/Build، Job/Cancel |

**اضافه کردن توسعه‌دهنده یا تأییدکننده:**

۱. کاربر را بسازید (یا اگر Jenkins به LDAP/AD وصل است، کاربر از قبل هست).
۲. **Manage Jenkins** ← **Manage and Assign Roles** ← **Assign Roles** ← در بخش **Item roles** کاربر (یا گروه LDAP) را اضافه کنید و تیک `paas-user` را بزنید.
۳. اگر تأییدکننده است، شناسه‌اش را در `approvers` سرویس‌های مربوط در `services.yaml` هم بگذارید. **تأییدکننده هم باید نقش `paas-user` را داشته باشد** تا build را ببیند و بتواند تأیید کند.

> ℹ️ `Job/Cancel` به توسعه‌دهنده اجازه می‌دهد درخواست منتظرِ خودش را لغو کند، ولی با همین دسترسی می‌تواند build **دیگران** را هم در پوشه‌ی `paas` متوقف کند. اگر این را نمی‌خواهید، `Job/Cancel` را از نقش بردارید (آن‌وقت فقط approver می‌تواند درخواست را با Abort رد کند).
>
> ⚠️ هرگز Job/Configure، Job/Workspace یا Credentials را به `paas-user` ندهید. با Configure هر کسی می‌تواند Jenkinsfile را عوض کند و به credentialها برسد.
>
> در lab، این تنظیمات از `lab/jenkins/casc.yaml` (JCasC) می‌آیند و با هر ری‌استارت Jenkins دوباره اعمال می‌شوند. تغییرات دستی در UI در lab ماندگار نیستند.

### ۵-۶. پیگیری (audit): چه کسی، چه چیزی، کی؟

| کجا | چه اطلاعاتی |
|---|---|
| **git** (repo استقرار هر سرویس) | هر deploy یک commit است: author = درخواست‌دهنده، و در پیام commit: `Requested-by`، `Approved-by`، `Jenkins-build` (لینک build) |
| **Jenkins** – Build History | توضیح هر build: «سرویس – requested by X, approved by Y»، و Console کامل شامل فایل |
| **روی سرور** – `<deploy_dir>/.compose-paas.json` | commit دقیقی که الان اجرا می‌شود، درخواست‌دهنده، تأییدکننده و لینک build |

<div dir="ltr">

```bash
# روی سرور: الان چه نسخه‌ای اجراست؟
cat /opt/apps/hello-web/.compose-paas.json
```

</div>

### ۵-۷. نصب روی Jenkins واقعی (production)

۱. **repo پایپ‌لاین‌ها**: همین پروژه را در GitLab سازمان push کنید (مثلاً `platform/compose-paas`).
۲. **repo تنظیمات**: `platform/paas-config` را با یک `services.yaml` بسازید (نمونه: `config-example/services.yaml`). فقط ادمین‌ها دسترسی نوشتن داشته باشند.
۳. **کاربر bot در GitLab**: یک کاربر (مثلاً `jenkins-bot`) با Personal Access Token با scopeهای `read_repository` و `write_repository`. روی repo پایپ‌لاین و تنظیمات دسترسی خواندن، و روی repoهای استقرار دسترسی push.
۴. **پلاگین‌ها**: فهرست کامل در `lab/jenkins/plugins.txt` (مهم‌ترین‌ها: `role-strategy`، `file-parameters`، `job-dsl`، `lockable-resources`، `pipeline-utility-steps`، `credentials-binding`، `git`).
۵. **agent**: یک agent با label **`paas`** که `git`، `ansible` و `ssh` روی آن نصب باشد.
۶. **credentialها** (Manage Jenkins ← Credentials ← System ← Global):
   - `gitlab-bot`: نوع *Username with password*؛ username = `jenkins-bot`، password = token.
   - `deploy-ssh`: نوع *SSH Username with private key*؛ username = `deploy`، کلید خصوصی.
۷. **متغیرهای سراسری** (Manage Jenkins ← System ← Global properties ← Environment variables):

| متغیر | مثال |
|---|---|
| `PAAS_CONFIG_REPO` | `https://gitlab.example.com/platform/paas-config.git` |
| `PAAS_CONFIG_BRANCH` | `main` |
| `PAAS_PIPELINE_REPO` | `https://gitlab.example.com/platform/compose-paas.git` |
| `PAAS_PIPELINE_BRANCH` | `main` |
| `PAAS_GIT_CRED` | `gitlab-bot` |
| `PAAS_SSH_CRED` | `deploy-ssh` |
| `PAAS_HOST_KEY_CHECKING` | `True` (بعد از پر کردن known_hosts) |

۸. **امنیت Job DSL**: Manage Jenkins ← Security ← *Enable script security for Job DSL scripts* را خاموش کنید، یا بعد از اولین اجرای sync اسکریپت را در *In-process Script Approval* تأیید کنید. (job sync فقط برای ادمین است و اسکریپتش از repo ادمین می‌آید.)
۹. **نقش‌ها**: مطابق [بخش ۵-۵](#۵-۵-کاربران-و-نقشها-در-jenkins).
۱۰. **job ادمین**: پوشه‌ی `paas-admin` بسازید و داخلش یک Pipeline با نام `sync-registry`: *Pipeline script from SCM* ← repo پایپ‌لاین‌ها ← Script Path: `jenkins/Jenkinsfile.sync`. فقط ادمین به این پوشه دسترسی داشته باشد.
۱۱. `sync-registry` را اجرا کنید. پوشه‌ی `paas` و دو job توسعه‌دهنده ساخته می‌شوند.
۱۲. با یک کاربر توسعه‌دهنده‌ی آزمایشی وارد شوید و بررسی کنید که فقط پوشه‌ی `paas` را می‌بیند.

### ۵-۸. تغییر رمزها و کلیدها

| چه چیزی | چطور |
|---|---|
| token کاربر bot | token جدید در GitLab بسازید ← credential `gitlab-bot` را در Jenkins به‌روز کنید ← token قدیمی را revoke کنید |
| کلید SSH deploy | کلید جدید بسازید ← public key را روی همه‌ی سرورها **اضافه** کنید ← credential `deploy-ssh` را عوض کنید ← یک deploy تست ← کلید قدیمی را از `authorized_keys` حذف کنید |

### ۵-۹. تغییر خود پایپ‌لاین‌ها

فایل‌های `jenkins/*` و `ansible/*` را در repo پایپ‌لاین‌ها تغییر دهید و push کنید. buildهای بعدی خودشان نسخه‌ی جدید را از git می‌خوانند. اگر **پارامترهای** jobها عوض شده (فایل `jenkins/jobs.groovy`)، `sync-registry` را اجرا کنید.

---

## ۶. محیط تست محلی (lab)

lab همه‌چیز را روی یک ماشین بالا می‌آورد: **GitLab CE 17.10.5** (همان نسخه‌ی GitLab سازمان)، **Jenkins** با همه‌ی تنظیمات، و یک **سرور مقصد** (Docker داخل Docker با SSH) که برنامه‌ها روی آن deploy می‌شوند.

<div dir="ltr">

```bash
cd ~/infra/docker-compose-platform

lab/up.sh        # بالا آوردن (بار اول چند دقیقه طول می‌کشد) – در پایان نام‌های کاربری و رمزها را چاپ می‌کند
tests/e2e.sh     # تست کامل از طریق API جنکینز (۴۰ بررسی)
lab/down.sh      # خاموش کردن (داده‌ها می‌مانند)
lab/down.sh --wipe   # خاموش کردن + پاک کردن همه‌ی داده‌ها و رمزها
```

</div>

| چه چیزی | آدرس | ورود |
|---|---|---|
| Jenkins | http://localhost:8090 | کاربران `admin`، `approver1`، `dev1`، `dev2`؛ رمزها در `lab/secrets/jenkins.env` |
| GitLab | http://localhost:8929 | کاربر `root`؛ رمز در `lab/.env` |
| برنامه‌های deploy شده | http://localhost:18080 تا 18089 | — |

<div dir="ltr">

```bash
# دیدن رمزها
cat lab/secrets/jenkins.env lab/.env
```

</div>

**سرویس‌های نمونه در lab:**

| سرویس | repo | مسیر فایل | approverها | پورت |
|---|---|---|---|---|
| `hello-web` | `platform/hello-web-deploy` | `deploy/docker-compose.yml` | approver1، admin | 18080 |
| `whoami` | `platform/whoami-deploy` | `compose/production/docker-compose.yml` | فقط approver1 | 18081 |

فایل‌های نمونه برای آپلود در `tests/fixtures/` هستند (`hello-v1.yml`، `hello-v2.yml`، `whoami.yml`).

**یک دور کامل تست دستی در lab:**

۱. با `dev1` وارد شوید ← **paas** ← **deploy-compose** ← **Build with Parameters** ← SERVICE = `hello-web`، فایل `tests/fixtures/hello-v2.yml` را آپلود کنید ← **Build**.
۲. Console را ببینید: فایل چاپ شده و build منتظر تأیید است. روی **Approve & deploy** بزنید ← پیغام می‌دهد که اجازه ندارید.
۳. در یک مرورگر دیگر (یا پنجره‌ی ناشناس) با `approver1` وارد شوید ← همان build ← **Approve & deploy**.
۴. صبر کنید تا SUCCESS شود. http://localhost:18080 را باز کنید: `hello-web v2`.
۵. در GitLab (با root) به `platform/hello-web-deploy` بروید و commit جدید را با `Requested-by: dev1` و `Approved-by: approver1` ببینید.
۶. با `dev1`: **show-compose** ← `hello-web` ← Console: فایل از git خوانده و نمایش داده می‌شود.

> lab فقط برای تست است: سرور مقصد `privileged` اجرا می‌شود، بررسی host key خاموش است، و رمزها در فایل‌های محلی‌اند (این فایل‌ها commit نمی‌شوند). اگر `jenkins/` یا `ansible/` را تغییر دادید، دوباره `lab/up.sh` را اجرا کنید تا به GitLab داخل lab push شوند.

---

## ۷. سؤالات متداول

**آیا می‌توانم فایل‌های دیگری مثل `.env` یا config هم بفرستم؟**
خیر، فعلاً فقط `docker-compose.yml`. متغیرهای ساده را مستقیم در `environment:` بنویسید (به‌جز رمزها). برای رمزها و فایل‌های config با ادمین هماهنگ کنید.

**اگر دو نفر هم‌زمان برای یک سرویس درخواست بفرستند چه می‌شود؟**
هر دو منتظر تأیید می‌مانند. بعد از تأیید، مرحله‌ی commit و deploy برای هر سرویس **قفل** دارد: درخواست‌ها پشت سر هم اجرا می‌شوند، نه هم‌زمان. آخری که اجرا شود، نسخه‌ی نهایی است. درخواست‌های سرویس‌های **متفاوت** موازی اجرا می‌شوند.

**یک درخواست منتظر تأیید، executor جنکینز را اشغال می‌کند؟**
خیر. مرحله‌ی تأیید بدون agent اجرا می‌شود؛ ده‌ها درخواست منتظر هیچ منبعی اشغال نمی‌کنند.

**اگر همان فایلی را که الان در git هست دوباره بفرستم؟**
commit جدیدی ساخته نمی‌شود (Console می‌گوید `nothing to commit`)، ولی همان فایل دوباره deploy می‌شود. این برای وقتی مفید است که کانتینرها روی سرور دستی تغییر کرده‌اند و می‌خواهید به حالت git برگردند.

**می‌توانم ببینم الان روی سرور دقیقاً چه چیزی اجرا می‌شود؟**
`show-compose` چیزی را نشان می‌دهد که در **git** هست. اگر آخرین deploy موفق بوده، همان روی سرور هم هست. اگر آخرین deploy با FAILURE تمام شده، ممکن است فرق داشته باشد. ادمین می‌تواند `.compose-paas.json` را روی سرور ببیند.

**چرا فایل قبل از deploy خودکار بررسی نمی‌شود؟**
در این نسخه تنها کنترل، تأیید انسانی است. اضافه کردن بررسی خودکار (اعتبار فایل با `docker compose config`، رد کردن `privileged`، `network_mode: host`، mount کردن `docker.sock` و ...) قبل از مرحله‌ی تأیید امکان‌پذیر است. اگر لازم دارید به ادمین پلتفرم بگویید.

**آیا ادمین می‌تواند بدون تأیید deploy کند؟**
از طریق این سیستم خیر؛ ادمین هم برای درخواست خودش به تأیید فرد دیگری نیاز دارد.

</div>
