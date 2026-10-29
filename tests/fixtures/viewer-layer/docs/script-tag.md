# Script tag file

Inline code keeps the raw markers as text: `</script>` and `<!-- not a comment -->`.

```html
<script>window.__pwned = true;</script>
<!-- fenced comment -->
```

Raw markup in a paragraph must be sanitised, never executed: <script>window.__pwned = true;</script> and <img src=x onerror="window.__pwned=true">.

Text after.
