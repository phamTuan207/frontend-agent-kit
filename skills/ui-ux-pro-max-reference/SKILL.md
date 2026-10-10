---
name: ui-ux-pro-max-reference
description: Consult the local UI UX Pro Max library when the user explicitly asks for Pro Max style, palette, typography, chart, or UX references or alternatives. Use as a reference lookup, not as the default frontend design workflow.
---

# UI UX Pro Max reference lookup

The reference copy is in `$HOME/.local/share/agent-design-references/ui-ux-pro-max`. Its source and version are recorded in `SOURCE.txt`. Consult `data/` or run a focused search:

```bash
python3 "$HOME/.local/share/agent-design-references/ui-ux-pro-max/scripts/search.py" 'editorial portfolio' --domain style --max-results 3
python3 "$HOME/.local/share/agent-design-references/ui-ux-pro-max/scripts/search.py" 'wellness app' --domain color --max-results 3
python3 "$HOME/.local/share/agent-design-references/ui-ux-pro-max/scripts/search.py" 'modern editorial' --domain typography --max-results 3
```

Check that each result fits the product and audience. Treat it as an option, while Impeccable or the user's chosen workflow leads the design. Do not use `--persist` unless the user asks for a design-system file.
