use std::path::PathBuf;

pub(super) fn install_opencode_plugin() -> anyhow::Result<()> {
    install_plugin(
        env_path("OPENCODE_CONFIG_DIR").unwrap_or(home_dir()?.join(".config/opencode")),
        "plugins/alera-agent-status.js",
        OPENCODE_PLUGIN,
    )
}

pub(super) fn install_pi_plugin() -> anyhow::Result<()> {
    install_plugin(
        env_path("PI_CODING_AGENT_DIR").unwrap_or(home_dir()?.join(".pi/agent")),
        "extensions/alera-agent-status.ts",
        PI_PLUGIN,
    )
}

pub(super) fn install_amp_plugin() -> anyhow::Result<()> {
    install_plugin(
        env_path("AMP_CONFIG_DIR").unwrap_or(home_dir()?.join(".config/amp")),
        "plugins/alera-agent-status.ts",
        AMP_PLUGIN,
    )
}

fn install_plugin(root: PathBuf, relative: &str, contents: &str) -> anyhow::Result<()> {
    let path = root.join(relative);
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(path, contents)?;
    Ok(())
}

fn home_dir() -> anyhow::Result<PathBuf> {
    dirs::home_dir().ok_or_else(|| anyhow::anyhow!("Could not resolve the user home directory."))
}

fn env_path(key: &str) -> Option<PathBuf> {
    std::env::var_os(key)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

const OPENCODE_PLUGIN: &str = concat!(
    "// ALERA_AGENT_STATUS_MANAGED_FILE\n",
    r#"async function aleraPost(agent,event,payload={}){const fs=await import('node:fs');const p=process.env.ALERA_AGENT_HOOK_ENDPOINT;if(p&&fs.existsSync(p)){for(const l of fs.readFileSync(p,'utf8').split(/\r?\n/)){const m=l.match(/^(?:set )?([A-Z0-9_]+)=(.*)$/);if(m)process.env[m[1]]=m[2]}}const port=process.env.ALERA_AGENT_HOOK_PORT,token=process.env.ALERA_AGENT_HOOK_TOKEN,terminalSessionId=process.env.ALERA_TERMINAL_SESSION_ID,workspaceId=process.env.ALERA_WORKSPACE_ID,tabId=process.env.ALERA_TAB_ID;if(!port||!token||!terminalSessionId||!workspaceId||!tabId)return;try{await fetch(`http://127.0.0.1:${port}/hook/${agent}`,{method:'POST',headers:{'Content-Type':'application/json','X-Alera-Agent-Hook-Token':token},body:JSON.stringify({terminalSessionId,workspaceId,tabId,payload:{hook_event_name:event,...payload}})})}catch{}}
export const AleraOpenCodeStatusPlugin=async()=>({event:async({event})=>{if(event?.type==='permission.asked')await aleraPost('opencode','PermissionRequest',event.properties);else if(event?.type==='question.asked')await aleraPost('opencode','AskUserQuestion',event.properties);else if(event?.type==='session.idle'||event?.type==='session.error')await aleraPost('opencode','SessionIdle');else if(event?.type==='session.status'&&['busy','retry'].includes(event?.properties?.status?.type))await aleraPost('opencode','SessionBusy');}});
"#
);

const PI_PLUGIN: &str = concat!(
    "// ALERA_AGENT_STATUS_MANAGED_FILE\n",
    r#"async function p(e,x={}){const fs=await import('node:fs');const f=process.env.ALERA_AGENT_HOOK_ENDPOINT;if(f&&fs.existsSync(f))for(const l of fs.readFileSync(f,'utf8').split(/\r?\n/)){const m=l.match(/^(?:set )?([A-Z0-9_]+)=(.*)$/);if(m)process.env[m[1]]=m[2]}const port=process.env.ALERA_AGENT_HOOK_PORT,token=process.env.ALERA_AGENT_HOOK_TOKEN,terminalSessionId=process.env.ALERA_TERMINAL_SESSION_ID,workspaceId=process.env.ALERA_WORKSPACE_ID,tabId=process.env.ALERA_TAB_ID;if(!port||!token||!terminalSessionId||!workspaceId||!tabId)return;try{await fetch(`http://127.0.0.1:${port}/hook/pi`,{method:'POST',headers:{'Content-Type':'application/json','X-Alera-Agent-Hook-Token':token},body:JSON.stringify({terminalSessionId,workspaceId,tabId,payload:{hook_event_name:e,...x}})})}catch{}}export default function(pi){pi.on('before_agent_start',e=>p('before_agent_start',{prompt:e.prompt??''}));pi.on('agent_start',()=>p('agent_start'));pi.on('tool_execution_start',e=>p('tool_execution_start',{tool_name:e.toolName,tool_input:e.args}));pi.on('tool_execution_end',e=>p('tool_execution_end',{tool_name:e.toolName}));pi.on('message_end',e=>e.message?.role==='assistant'&&p('message_end',{role:'assistant',text:e.message.content}));pi.on('agent_end',()=>p('agent_end'));pi.on('session_shutdown',()=>p('session_shutdown'));}
"#
);

const AMP_PLUGIN: &str = concat!(
    "// ALERA_AGENT_STATUS_MANAGED_FILE\n",
    r#"async function p(e,x={}){const fs=await import('node:fs');const f=process.env.ALERA_AGENT_HOOK_ENDPOINT;if(f&&fs.existsSync(f))for(const l of fs.readFileSync(f,'utf8').split(/\r?\n/)){const m=l.match(/^(?:set )?([A-Z0-9_]+)=(.*)$/);if(m)process.env[m[1]]=m[2]}const port=process.env.ALERA_AGENT_HOOK_PORT,token=process.env.ALERA_AGENT_HOOK_TOKEN,terminalSessionId=process.env.ALERA_TERMINAL_SESSION_ID,workspaceId=process.env.ALERA_WORKSPACE_ID,tabId=process.env.ALERA_TAB_ID;if(!port||!token||!terminalSessionId||!workspaceId||!tabId)return;try{await fetch(`http://127.0.0.1:${port}/hook/amp`,{method:'POST',headers:{'Content-Type':'application/json','X-Alera-Agent-Hook-Token':token},body:JSON.stringify({terminalSessionId,workspaceId,tabId,payload:{hook_event_name:e,...x}})})}catch{}}export default function(amp){amp.on('agent.start',e=>p('agent.start',{message:e?.message}));amp.on('tool.call',e=>{p('tool.call',{tool:e?.tool,input:e?.input});return{action:'allow'}});amp.on('tool.result',e=>p('tool.result',{tool:e?.tool,status:e?.status}));amp.on('agent.end',e=>p('agent.end',{status:e?.status,messages:e?.messages}));}
"#
);
