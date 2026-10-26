# Security

Bilge acts on your computer and reads mail, pages and documents, so security reports matter to us.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private reporting instead:
[Report a vulnerability](https://github.com/coderssociety/bilge-assistant/security/advisories/new). Include what an
attacker could do, the steps or the text that triggers it (for example a web page or an e-mail that makes Bilge act),
and the app and version.

We aim to answer within a week and to fix confirmed issues in the next release, crediting you if you wish.

## In scope

- Text read from a web page, an e-mail, a document or the clipboard making Bilge act without the user's yes
  (prompt injection).
- An action that should ask first running without a confirmation.
- API keys, tokens or recordings leaving the computer, or reaching anyone but the service the user chose.
- The in-app updater installing something other than the project's own, checksum-verified release.

Only the latest release is supported.

---

**Türkçe:** Bir güvenlik açığını herkese açık bir issue olarak değil, yukarıdaki bağlantıdan GitHub'ın gizli
bildirimiyle ilet.
