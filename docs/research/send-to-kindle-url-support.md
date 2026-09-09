# Send to Kindle: Does the Email Pathway Accept a URL Instead of an Attachment?

_Research date: 2026-09-08. Sources are Amazon first-party help pages unless noted._

## Question

Does Amazon's "Send to Kindle" **email** pathway (sending to an `@kindle.com` address) support putting a **URL/link** to an ebook file (e.g. an EPUB on a web server) in the email **body**, so that Amazon's servers download it, convert it, and deliver it to the Kindle? Or does the email pathway strictly require the document as a **file attachment**? Also: supported formats, size limit, whether any other Send to Kindle channel accepts a link, and any statement about Amazon making outbound fetches to third-party URLs.

## Answer

**No. The `@kindle.com` email pathway requires the document as a file attachment.** Every Amazon help page describing the email flow instructs the user to "attach" / "send your file as an attachment," and the official error table returns error **E009 "No Attachment" – "The sent email does not include any attachment(s). Please attach the document(s)…"** when an email arrives with no attachment. There is no documented mechanism for Amazon to fetch a URL placed in the email body. Links are only handled by the **client-side** channels — the Send to Kindle browser extension and the iOS/Android app share sheet — which capture or render the web page on the user's own device/browser and upload the result; no Amazon help page describes Amazon's servers making outbound fetches to arbitrary third-party URLs.

## Evidence

### 1. The email flow requires an attachment; a URL in the body is not fetched

- **"Learn How to Use Your Send to Kindle Email Address"** (Amazon Customer Service, nodeId `G7NECT4B4ZWHQ8WV`):
  > "For your email to be delivered successfully: … Verify that the document is a supported file type. **Attach the document to your email.** Be sure that your device is connected to the internet."
  URL: https://www.amazon.com/gp/help/customer/display.html?nodeId=G7NECT4B4ZWHQ8WV

- **"Send to Kindle for Email"** (amazon.com/sendtokindle/email), step 3:
  > "**Send your file as an attachment** to your Send to Kindle email address. You don't need to include a subject line."
  URL: https://www.amazon.com/sendtokindle/email

- **"Learn About Sending Documents to Your Kindle Library"** (nodeId `G5WYD9SAF7PGXRNA`), "Send to Kindle for Email" section:
  > "**Send your file(s) as an attachment** to your Send to Kindle email address."
  URL: https://www.amazon.com/gp/help/customer/display.html?nodeId=G5WYD9SAF7PGXRNA

- **"Troubleshoot Send to Kindle Errors"** (nodeId `T48rsVm3gY7KeGkKUk`), error **E009**:
  > "**No Attachment** — The sent email does not include any attachment(s). Please attach the document(s) and try sending the email again."
  This is the decisive statement: an email whose body contains only a link, with no attachment, is rejected with E009 and nothing is delivered.
  URL: https://www.amazon.com/gp/help/customer/display.html?nodeId=T48rsVm3gY7KeGkKUk

- No Amazon help page for the email flow mentions URLs, links, "download," or "fetch" in the email body. The feature simply does not exist in the documentation.

### 2. Supported file formats (email / Send to Kindle)

- **nodeId `G5WYD9SAF7PGXRNA`**, "Send to Kindle – Supported File Formats":
  > "Send to Kindle supports the following file types: HTML (.HTML, .HTM), RTF (.RTF), Text (.TXT), JPEG (.JPEG, .JPG), GIF (.GIF), PNG (.PNG), BMP (.BMP), PDF (.PDF), EPUB (.EPUB)."
  URL: https://www.amazon.com/gp/help/customer/display.html?nodeId=G5WYD9SAF7PGXRNA

- **amazon.com/sendtokindle** and **/sendtokindle/email** list a slightly longer set (Word formats included):
  > "Supported File Types: PDF, DOC, DOCX, TXT, RTF, HTM, HTML, PNG, GIF, JPG, JPEG, BMP, EPUB"
  URLs: https://www.amazon.com/sendtokindle , https://www.amazon.com/sendtokindle/email
  (The error table confirms DOC/DOCX are accepted: E003 "Unsupported MS Word Format … created using MS Word 97 or newer … (.DOC) or Office Open XML format (.DOCX)".)

- **MOBI / AZW is deprecated.** Amazon wound down MOBI (`.mobi`, `.azw`, `.prc`) for Send to Kindle starting 1 Nov 2023 and ended it by ~20 Dec 2023; the current supported ebook format for personal documents is **EPUB**. The live help pages above no longer list MOBI/AZW as supported, and the error table still references legacy "Invalid or Corrupted MOBI File" (E002) only for already-in-library handling. (Secondary confirmation: The eBook Reader / Hacker News threads citing Amazon's notice — see Sources.)

### 3. Size limit (email)

- **nodeId `G7NECT4B4ZWHQ8WV`**:
  > "Send up to **25 attachments** in one email. Send to your Send to Kindle email from up to **15 approved email addresses**. **Send a total size of 50 MB or less.** Compress your documents into a ZIP file to send more than 50 MB. The conversion service automatically opens the ZIP files and converts them to the Kindle format."
  URL: https://www.amazon.com/gp/help/customer/display.html?nodeId=G7NECT4B4ZWHQ8WV

- **Error table** (nodeId `T48rsVm3gY7KeGkKUk`): E007 "Attachment Size Limit Exceeded … ensure that **each attachment does not exceed 50 MB** in size (before compression if zipped)"; E006 "more than 25 documents"; E008 "more than 15 recipients."
  URL: https://www.amazon.com/gp/help/customer/display.html?nodeId=T48rsVm3gY7KeGkKUk

- Note the contrast: **Send to Kindle for Web** allows **"documents (200 MB or smaller)"** (nodeId `G5WYD9SAF7PGXRNA`; also stated as "Max File Size: 200 MB" on amazon.com/sendtokindle). The 50 MB cap is specific to the email channel.

### 4. Which channels take a link/URL rather than a file

| Channel | Takes a link? | How it works (per Amazon docs) |
|---|---|---|
| **Email (`@kindle.com`)** | **No** | "Attach the document to your email." URL in body → E009 "No Attachment." |
| **Send to Kindle for Web** (amazon.com/sendtokindle) | No | "Upload documents (200 MB or smaller) directly from your device." File picker only. |
| **Send to Kindle Chrome/browser extension** | **Yes — the page you are on** | "Send web content like articles, blog posts, and more, to your Kindle library." "On the page you want to send, click the Kindle icon… 'Quick send' instantly sends full pages… 'Send selection' just sends selected text." The extension captures the **currently open page in your browser** (client-side); you do not type an arbitrary URL for Amazon to fetch. Source: https://www.amazon.com/sendtokindle/chrome |
| **Kindle app for iOS / Android (share sheet)** | **Yes — via the OS share sheet** | "Add personal documents, web content, and other files… Open or select the file you want to send and tap the Share icon. Select Kindle in the sharing options." When you share a web page URL from Safari/Chrome, the Kindle app's share extension renders/extracts the page **on the device** and uploads it. Sources: https://www.amazon.com/sendtokindle/ios , https://www.amazon.com/sendtokindle/android |
| **Send to Kindle desktop apps (Mac / Windows)** | No | "Send documents from your desktop directly to your Kindle library." Local files (and, on Mac, a USB file manager). Source: https://www.amazon.com/sendtokindle/mac |

There is a web-content **error code** — E015 "Web Extraction Error … A webpage (HTML file) sent via Send to Kindle could not be delivered due to content extraction errors" — but it refers to an **HTML file that was attached/shared**, not to a URL fetched from an email body.

### 5. Statements about Amazon making outbound fetches to third-party URLs

- **None found.** No first-party Send to Kindle page describes Amazon's infrastructure retrieving a file or page from a user-supplied third-party URL. The only server-side processing Amazon documents is: opening attached ZIP files, converting attached documents to Kindle format, and extracting readable content from attached/shared HTML. All URL/"web content" handling in the docs is performed by client software (browser extension, mobile share extension) before upload.
- Amazon does state the transport is protected: "All documents sent through Send to Kindle are protected with end to end encryption" (nodeId `G5WYD9SAF7PGXRNA`), and "The delivery for your documents will be attempted for up to 60 days" (nodeId `G7NECT4B4ZWHQ8WV`).

## Implications for Folio

- **The "just email a URL instead of attaching the file" workaround does not work.** Folio's Send to Kindle feature must attach the actual ebook file to the message to `@kindle.com`. An email with a download link in the body and no attachment is rejected by Amazon with E009 and never reaches the device. The current `SendToKindleService` approach (SMTP with the file as a MIME attachment) is the only supported design.
- **Enforce the 50 MB per-attachment / 50 MB total / 25-file limits** before sending, and surface a clear toast if exceeded (map to Amazon's E006/E007). For very large books, the only Amazon-sanctioned mitigation is zipping; Folio could also point the user at WiFi transfer instead.
- **Preferred outbound format is EPUB or PDF.** Do not attempt to send MOBI/AZW via email — Amazon dropped it end-2023 and it will bounce. This aligns with Folio already treating EPUB as primary; conversion to MOBI is only relevant for USB sideloading, not Send to Kindle.
- **If Folio ever wants "send a web article" behaviour, it cannot lean on the email channel** — that is the browser-extension / mobile-share-sheet job (client renders the page, then uploads). Out of scope for the current macOS MVP; note it as a non-goal.

## Sources

First-party (Amazon):
- https://www.amazon.com/sendtokindle — Send to Kindle landing; format list, "Max File Size: 200 MB" (web uploader), list of channels
- https://www.amazon.com/sendtokindle/email — "Send your file as an attachment"; format list
- https://www.amazon.com/sendtokindle/chrome — browser extension: "Send web content like articles, blog posts"; Quick send / Send selection
- https://www.amazon.com/sendtokindle/ios — iOS: share icon → Kindle
- https://www.amazon.com/sendtokindle/android — Android: share icon → Kindle
- https://www.amazon.com/sendtokindle/mac — Mac desktop app + USB file manager
- https://www.amazon.com/gp/help/customer/display.html?nodeId=G5WYD9SAF7PGXRNA — "Learn About Sending Documents to Your Kindle Library": per-channel overview, supported formats, end-to-end encryption
- https://www.amazon.com/gp/help/customer/display.html?nodeId=G7NECT4B4ZWHQ8WV — "Learn How to Use Your Send to Kindle Email Address": "Attach the document to your email"; 25 attachments / 15 addresses / 50 MB / ZIP; 60-day retry
- https://www.amazon.com/gp/help/customer/display.html?nodeId=T48rsVm3gY7KeGkKUk — "Troubleshoot Send to Kindle Errors": E009 "No Attachment", E006/E007/E008 limits, E003 Word formats, E015 "Web Extraction Error"
- https://www.amazon.com/gp/help/customer/display.html?nodeId=TWXpUGw76dtEg2VD9P — "Tips about converting personal documents to a Kindle format" (linked from /sendtokindle/email; not directly retrieved this session)
- https://www.amazon.com/gp/help/customer/display.html?nodeId=TNtSm13k3txFI4EvDV — "Kindle personal document file types that support notes" (linked from /sendtokindle/email; not directly retrieved this session)

Note on access: `amazon.com/gp/help/customer/display.html` pages intermittently returned Amazon's generic error page from this environment; the quoted text for nodeIds `G5WYD9SAF7PGXRNA`, `G7NECT4B4ZWHQ8WV`, and `T48rsVm3gY7KeGkKUk` was read from the identical pages on `amazon.co.uk` (same Amazon help content, same nodeIds). The `amazon.com/sendtokindle*` pages were read directly.

Secondary (used only to locate/confirm the MOBI-deprecation timeline, not relied on for the verdict):
- https://blog.the-ebook-reader.com/2022/05/03/amazon-dropping-mobi-support-on-send-to-kindle-apps/
- https://news.ycombinator.com/item?id=37652898 — "Final Reminder: Send to Kindle Will No Longer Support MOBI File Formats"
