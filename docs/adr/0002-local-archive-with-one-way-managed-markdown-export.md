# Keep the local archive authoritative and export Markdown one way

Chronicle's encrypted local archive is the source of truth; Markdown integration is a one-way projection into Chronicle-owned delimited blocks. This preserves an auditable in-app history and allows Obsidian or other editors to own everything outside the managed block, while deliberately rejecting ambiguous two-way merge semantics that could silently rewrite reviewed history.
