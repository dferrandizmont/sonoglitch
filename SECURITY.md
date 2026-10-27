# Security policy

## Supported versions

Only the latest alpha release is supported for security fixes. Earlier alphas and unreleased branches may contain known issues. Alpha builds are experimental; a supported version is not a guarantee of device validation.

## Report a vulnerability privately

On this repository's GitHub page, open **Security > Advisories > Report a vulnerability** to use GitHub private vulnerability reporting. Do not put vulnerability details, private photos, diagnostic reports or credentials in a public issue or pull request.

You can also write to dev@mainshai.com. If neither channel works, open a public issue asking only for a private reporting channel, without reproduction steps or sensitive details, and do not send the vulnerability itself until a private channel is available.

Include the affected version or commit, platform, prerequisites, expected impact and minimal reproduction steps. Use synthetic images and sanitized diagnostics where possible. Never include audio recordings, secrets or other people's data.

## Scope

Reports about Sonoglitch's app code, native configuration, bundled dependencies and repository build/release automation are welcome. Examples include unintended microphone use, audio storage or transmission, unintended network activity, exposure of local photos or diagnostics, permission bypasses and unsafe handling of image or sensor input. Findings in third-party packages are relevant when they affect this app; coordinate upstream disclosure privately as needed.

Ordinary crashes, visual defects, sensor calibration and feature requests belong in public issues after checking that they contain no private information. General operating-system issues and unrelated services are outside this project's scope.

## Response and disclosure

This is a small project without a dedicated security team. Maintainers aim to acknowledge a private report within seven days and provide an initial assessment within fourteen days, but these are targets, not guarantees. Fix timing depends on severity, available maintainers and device validation. Please coordinate publication with the maintainers so a fix or mitigation can be prepared; there is no promised bounty or fixed disclosure deadline.
