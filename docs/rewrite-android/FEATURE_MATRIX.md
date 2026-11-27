# Android Feature Rewrite Progress Matrix

Ordered dependency graph for `android-next/` (`F-00` through `F-08`).

| ID | Feature Name | Dependencies | Backend Bridge | Compose + Liquid Glass | Unit Tests | HIG / Unslop Sign-Off | Guardrail Sign-Off | Status |
| :--- | :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| F-00 | Greenfield Project, Core AAR Hardening & Liquid Glass Shell | None | [x] | [x] | [x] | [x] | [x] | DONE |
| F-01 | Tailscale Auth (Custom Tabs), Sign-Out & Device Rename | F-00 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-02 | Peer Discovery, Presence & Search | F-01 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-03 | Multi-File SAF Staging & Floating Glass Dock | F-00 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-04 | Single & Batch Send, Concurrent Progress & Cancel | F-02, F-03 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-05 | 3-Slot Incoming Approval Queue, Notifications & Trust Circle | F-01 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-06 | Transfer History, Atomic MediaStore/SAF Save & FileProvider Open | F-04, F-05 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-07 | Settings Tab & Persistable Download Folder | F-01, F-05 | [x] | [x] | [x] | [x] | [x] | DONE |
| F-08 | Android 15 Foreground Service & Liquid Glass Share Target | F-03, F-05 | [x] | [x] | [x] | [x] | [x] | DONE |
