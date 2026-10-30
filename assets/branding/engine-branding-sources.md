# Engine branding source review

Checked 2026-10-29. No unofficial, AI-created, APK-extracted or cropped engine
marks were added. Existing niraNG artwork is unaffected.

## Psiphon VPN: official new icon identified; bytes not acquired

- Official source page: <https://www.psiphon.ca/en/about>.
- The page's August 2026 “New Psiphon VPN released” timeline entry labels the
  following exact asset “Psiphon VPN app icon”:
  <https://www.psiphon.ca/img/about/psiphon_favicon_svg_square_v1.svg>.
- Intended local source filename, once the original bytes can be acquired:
  `assets/branding/psiphon-official.svg`. It has **not** been created.
- SVG dimensions, byte count and SHA256 are unverified because the local download
  did not complete. No hash or derived PNG is invented.
- Bounded download checks: official `www.psiphon.ca` timed out; `psiphon.ca`
  reset TLS; the existing local SOCKS/HTTP development proxies also timed out.
  No VPN profile or system network setting was changed. The official historical
  website repository at commit `13d1e3fa96d01a0adfa04002c4aa2513f94f2ff4`
  does not contain this new asset, so its older favicon was not substituted.
- Attribution: Psiphon VPN app icon, Psiphon Inc.; official asset URL above.
- The official website footer links site content to CC BY 3.0:
  <https://creativecommons.org/licenses/by/3.0/>.
- The separate Terms of Service, dated September 28, 2026, section 4 reserve
  Psiphon's marks and require prior written permission for their use:
  <https://www.psiphon.ca/en/license.html>.
  The site-content license is not presented here as trademark permission.
- If an authorized production use is selected later, preserve the untouched
  source SVG and its actual SHA256. A deterministic 128-pixel PNG render may be
  derived without changing aspect ratio, shape or colors; record its renderer
  and separate hash. It must not claim affiliation or endorsement.

## Aether: official banner inspected; no standalone logo asset imported

- Official repository: <https://github.com/CluvexStudio/Aether>.
- Reviewed tree: `d58f9d568083129ce2c767c85054021eb3ee6a38`.
- The only Aether artwork found in that tree is
  `Docs/Aether_ar.png`, blob `e423f6af0235b6d546667688f6065e44e655d746`:
  <https://raw.githubusercontent.com/CluvexStudio/Aether/d58f9d568083129ce2c767c85054021eb3ee6a38/Docs/Aether_ar.png>.
- This image was visually inspected. It is a 2560 × 1280 RGB banner containing
  the Aether title, descriptive text and an abstract A-shaped graphic. It is not
  an isolated square app icon. It was not cropped into an invented logo or
  copied into production assets.
- The inspection copy remains only in ignored build output:
  `build/branding-sources/aether-candidate.png`.
  SHA256: `fec97ed71010a84b6253c740303432c5a8f49ba673c09f21867b9992db0b2e01`.
- Attribution: Aether / CluvexStudio; exact source URL above.
- The project's explicit trademark policy says its source-code AGPL license
  does not grant branding rights and requires prior written permission to use
  its name/logo/branding in derivative products or clients:
  <https://github.com/CluvexStudio/Aether/blob/d58f9d568083129ce2c767c85054021eb3ee6a38/TRADEMARK.md>.
- No `aether-official.*` production asset was created. A neutral existing
  network glyph can identify the engine without pretending to be its logo.


## 2026-10-30 official yellow icon retrieval retry

The owner explicitly selected the modern yellow Psiphon icon and rejected the
legacy orange/red P. The target remains the untouched official SVG linked by
Psiphon's current About/Download pages:
<https://www.psiphon.ca/img/about/psiphon_favicon_svg_square_v1.svg>.
The live web reader confirms the image URL but cannot export SVG bytes.

A bounded retry did not acquire the source: three command-local public UDP DNS
queries all returned the poisoned address 10.10.34.36; Cloudflare/Google HTTPS
DNS timed out or reset. Certificate-verified HTTPS with local `--resolve` against
104.18.14.196 and 104.18.15.196 also reset. Case and alternate Cloudflare-route
checks failed. No global DNS, VPN, profile, hosting or credentials were changed.
The official public historical website source has no copy of this new SVG.

No yellow SVG or derived PNG was fabricated, recolored, cropped or substituted.
The existing `psiphon-official.png` is the earlier legacy Android P asset, not
this selected modern yellow icon; it must not be represented as the requested
new icon. Replacing it remains pending successful original-source acquisition.


## 2026-10-30 resolved: modern official artwork acquired

The earlier retrieval blocker above is resolved. A command-local HTTPS DNS query to Google Public DNS verified the origin, and a bounded Google Translate HTTPS proxy request fetched the untouched current official SVG and the exact apple-touch icon declared in the current official page. No global DNS/VPN change was made.

Production `psiphon-official.png` now contains the official modern 180x180 PNG, not the rejected legacy Android P. It was copied without recoloring, cropping or pixel alteration. The original SVG is retained as `psiphon-official.svg`. Source URLs and SHA256 values are recorded in `psiphon-source.json`. Identification of the engine does not imply affiliation or endorsement.

## 2026-10-30 follow-up: sharper vector raster without the apple-icon rim

The original retained SVG is now rendered at its native400x400 using isolated
headless Chrome. The production PNG replaces the lower-resolution apple-touch
icon, which had a baked white border; shape and source colors are unchanged.
PsiphonBrandIcon applies the app's rounded clipping/high-quality sampling.
Source/provenance and the separate raster hash remain in psiphon-source.json.
