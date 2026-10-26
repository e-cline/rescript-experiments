---
'@e-cline/weft_dom': patch
---

Controlled radio buttons keep the one their state checks: after an event, the other radio buttons in
the group of the one it happened on (the same `name`, in the same form) get their controlled
`checked` back too, since checking one unchecks them with no event of their own.
