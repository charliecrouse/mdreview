---
name: mdreview
description: Ask the user to review a Markdown file (plan, spec, doc) in the mdreview app and act on their comments. Use when you wrote or changed a Markdown file the user should review, or when they say they left comments in mdreview.
---

# mdreview review loop

1. **Request the review.** Run `mdreview <file.md>`. It opens the file in the app and blocks until the user presses Send to Agent, then prints the review and exits 0. Exit 1 means the file was closed or the app quit unsent. In Claude Code run it with `run_in_background: true` and carry on or stop; you are woken when it exits. Elsewhere run it in the foreground.
2. **Read the review.** The output is the command's output. Each comment has a line range, the quoted text, the reviewer's note and an `id`. If you already replied to a comment, your earlier reply is shown under it.
3. **Edit the file** to address each comment. The app reloads it and keeps comments anchored.
4. **Reply to each comment:** `mdreview reply <file.md> <id> "what you did" --resolve`. Without `--resolve` it is a question or a partial answer. `--resolve` only says you think it is handled; the reviewer confirms. Reply with the id from the review, never a line number.
5. **Ask again.** Run `mdreview <file.md>` once more. If the user sent a review while nothing was waiting, it prints immediately.

Outdated comments quote text the file no longer contains; check whether they still apply. Don't write to `~/Library/Application Support/mdreview/`; the commands manage it.
