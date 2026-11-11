# Contributing

## Release process

1. Run the release checks against the final candidate. Prepare the release metadata by replacing `Unreleased` in
   `CHANGELOG.md` with the release date and confirming that the version in `pubspec.yaml` matches the release.
2. If the package does not yet exist on pub.dev, its owner must publish the first version manually from the owner's
   pub.dev account. A GitHub tag cannot create the package through the release workflow before this first publication.
3. For an existing package, the owner may choose either to keep publishing later versions manually or to set up pub.dev
   automated publishing for this repository. Automated publishing requires pub.dev to authorize the repository and its
   GitHub Actions OIDC identity; the existence of this workflow does not confirm that authorization or upload access.
   The current workflow still attempts to publish on every matching tag, so the owner must account for that job when
   choosing manual publishing for later versions.
4. When using the automated path, after the owner has confirmed pub.dev authorization, create a GitHub release with a
   tag of `v<version>` (for example, `v4.0.0`). The release workflow runs its test job first, then attempts to publish
   using OIDC. It publishes only when the package and automated publishing authorization are already in place.
