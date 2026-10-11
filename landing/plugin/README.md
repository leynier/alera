# Alera Plugin

Connect your AI client to Alera to manage workspaces, coding agents, pull requests, and automations. This package includes the remote MCP connection, four Alera MCP workflow skills with all their references, a setup skill, and the Alera logo.

## Before You Connect

1. Install and open [Alera](https://alera.build/download) on the machine you want to control.
2. Sign in under **Settings > Account**.
3. Under **Settings > MCP Access > MCP Control**, choose read access for inspection or full access for actions. Full access allows commands on this machine. Administrative access is a separate choice.

## Install The Downloaded Package

Extract `alera-plugin.zip`. Keep the resulting `alera` folder intact, including its hidden `.agents` and `.codex-plugin` directories.

For Codex and Codex in the ChatGPT desktop app, register the extracted folder as a local marketplace:

```sh
codex plugin marketplace add /path/to/alera
codex plugin add alera@alera
```

Replace the path with your extracted folder; quote it if it contains spaces. The second command installs and enables the plugin in Codex. If you prefer the desktop interface, run only the first command, restart the ChatGPT desktop app, open the Plugins Directory, choose **Alera**, and install the **Alera** plugin from that source. Complete the Alera OAuth connection and run the plugin's setup workflow. Client and workspace policies determine which installation and authentication controls are available.

In ChatGPT on the web, you can connect the existing remote MCP directly: open [Plugins](https://chatgpt.com/plugins), select **Add custom MCP server**, use `https://api.alera.build/v1/mcp`, select OAuth, and complete the connection. This connects the MCP tools; it does not install the skills in this ZIP. To use the complete package in the public Plugins Directory, the publisher must submit this ZIP to OpenAI and publish it after approval.

## Try It

- "Help me connect Alera and show my available runtimes."
- "Show the workspaces and coding agents running in Alera."
- "Start an Alera workspace for my next coding task."

OAuth credentials are never included in this package. Choose the intended runtime and permission level in the connection flow. Installation does not start a runtime or enable its MCP Control setting.

For current instructions and troubleshooting, see [Install The Alera Plugin](https://alera.build/docs/plugin). Data handling is described in the [Privacy Policy](https://alera.build/privacy).
