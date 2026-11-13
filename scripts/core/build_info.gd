class_name BuildInfo
extends RefCounted
## Which build is running, shown in the corner of the main menu. tools/stamp_build.ps1 rewrites LABEL before
## every export (commit and time), so "is this the new version?" can be answered by looking at the menu.
const LABEL: String = "build f29239f  |  2026-11-13 18:53"
