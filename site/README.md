# Website

Last Monday's website: the landing page, the privacy policy, the terms of use and the support page. Plain HTML and CSS with no build step. `.github/workflows/pages.yml` publishes this folder to GitHub Pages when it changes on `main`, at https://j23n.github.io/caniretireyet/.

| Page | Path |
| --- | --- |
| Landing page | `index.html` |
| Privacy policy | `privacy/index.html` |
| Terms of use | `terms/index.html` |
| Support | `support/index.html` |

- The text pages share `assets/page.css`. The landing page carries its styles inline, and draws the app's screens in HTML.
- The landing page's numbers come from the made-up example library (`Sources/TestSupport/Resources/ExampleLibrary/`). Keep them made up.
- The privacy policy describes what the app sends and stores. When the app starts calling a new service (a price source in `Sources/Prices`, say) or keeps data somewhere new, update the policy in the same change.
- Links between pages are relative, so the site works at any path.

To preview, run `python3 -m http.server` in this folder and open http://localhost:8000.
