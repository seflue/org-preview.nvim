# Changelog

All notable changes to `org-preview.nvim` are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

<!-- next-header -->

## [Unreleased]

### Added

- `:OrgPreview` / `:OrgPreviewStop` / `:OrgPreviewToggle`: live browser
  preview of the current Org buffer, unsaved, via pandoc and a pure-Lua
  `vim.uv` HTTP server with Server-Sent Events.
- Pluggable backends (`cmd` or `render` function); `pandoc` built in.
- Configurable stylesheets, default water.css; table of contents.
- Free port per Neovim instance (`port = 0`), kept across stop/start so open
  tabs reconnect; fixed port still configurable.
- `:checkhealth org-preview`.

<!-- next-url -->
[Unreleased]: https://github.com/seflue/org-preview.nvim/commits/HEAD
