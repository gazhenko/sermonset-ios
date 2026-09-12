# SermonSet working agreement

Use native Swift and SwiftUI. Preserve the original product handoff and owner
decisions supplied in each Project Desk task. Implement only the assigned slice.

Use XcodeGen if useful; it is installed at /opt/homebrew/bin/xcodegen. Keep
generated build output, DerivedData, and temporary fixtures inside ignored
workspace directories. Do not install dependencies or require network access.
Record exact build/test commands and outcomes in docs/REVIEW.md.

Simulator build and launch evidence is distinct from physical iPhone validation.
If the execution environment cannot run a required check, report it as blocked;
never fabricate a passing result. Avoid modifying shared simulators or credentials.

All app features are free. Private use requires no account. Do not implement
public uploads, analytics containing private content, trading, or licensing policy
as part of a capture task. Retain original audio and protect local recordings.

Manager workers must not commit, push, deploy, sign releases, access credentials,
or modify the coordinator. The coordinator retains isolated commits and reviews.
