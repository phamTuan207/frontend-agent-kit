---
name: threeui
description: Use when the user asks to browse, install, adapt, or integrate a ThreeUI component from Meng To's ThreeUI catalog into a frontend. Covers the official open Community React package and component assets. Do not invoke for general Three.js work or unrelated UI design.
---

# ThreeUI components

ThreeUI is a component library, not a design method. Use it for a specific 3D or shader component that fits the user's product. Coordinate its visual direction with the project's existing design and, when available, the `impeccable` skill.

1. Inspect the current project stack and the [official ThreeUI Community catalog](https://threeui.com/) or [source repository](https://github.com/MengTo/threeui). Choose a named component and check its dependencies, controls, variants, and asset needs before adding it.
2. For free Community React components, the official package is `@designcodeio/threeui`. Import the chosen component and `@designcodeio/threeui/style.css`. Prefer a component subpath import if the project benefits from a smaller development import graph. Install the package only in the relevant project as part of the authorized implementation task.
3. Some components need runtime assets at root-relative URLs. Copy only the required files from the package's `lib-dist/assets/` into the app's public directory, or use the component's `sourceUrl` / `assetBaseUrl` prop when available. Verify the built page in the browser, including mobile sizing and loading behavior.
4. Pro source is separate and requires an entitled account through the official CLI. Do not claim a Pro component is available from the Community npm package.

Reference: [official repository and installation notes](https://github.com/MengTo/threeui#install-the-react-package).
