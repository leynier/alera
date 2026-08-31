use std::io::{BufRead as _,BufReader,Write as _};
use std::net::{Shutdown,TcpListener,TcpStream};
use std::path::PathBuf;
use std::sync::{Arc,Mutex,mpsc,atomic::{AtomicBool,Ordering}};
use std::time::{Duration,Instant};
use serde_json::{Value,json};

use crate::runtime_bridge::RuntimeBridge;

pub(crate) struct ControlledRuntime {
    requests:mpsc::Receiver<ControlledRequest>,
    writer:Arc<Mutex<TcpStream>>,
    directory:PathBuf,
    server:Option<std::thread::JoinHandle<()>>,
}

pub(crate) struct ControlledRequest {
    pub kind:String,
    pub payload:Value,
    id:i64,
    writer:Arc<Mutex<TcpStream>>,
}

pub(crate) fn pair()->(RuntimeBridge,ControlledRuntime) {
    let directory=std::env::temp_dir().join(format!("alera-controlled-runtime-{}",uuid::Uuid::new_v4()));
    std::fs::create_dir(&directory).unwrap();
    #[cfg(unix)] {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&directory,std::fs::Permissions::from_mode(0o700)).unwrap();
    }
    let listener=TcpListener::bind(("127.0.0.1",0)).unwrap();
    let port=listener.local_addr().unwrap().port();
    let token=uuid::Uuid::new_v4().to_string();
    std::fs::write(directory.join("host.json"),serde_json::to_vec(&json!({
        "protocolVersion":4,"port":port,"token":token,
        "runtimeCapabilities":["runtimeStore","sshTargetBootstrap","managedWorkspaceLifecycle"]
    })).unwrap()).unwrap();
    let (sender,requests)=mpsc::channel();
    let (ready,connected)=mpsc::channel();
    let server=std::thread::spawn(move||{
        let (stream,_)=listener.accept().unwrap();
        stream.set_nodelay(true).unwrap();
        let writer=Arc::new(Mutex::new(stream.try_clone().unwrap()));
        ready.send(writer.clone()).unwrap();
        let mut reader=BufReader::new(stream);
        loop {
            let mut line=String::new();
            match reader.read_line(&mut line) {Ok(0)|Err(_)=>break,_=>{}}
            assert!(line.len()<1024*1024,"unexpected fixture request size");
            let request:Value=serde_json::from_str(&line).unwrap();
            let id=request["id"].as_i64().unwrap();
            let kind=request["type"].as_str().unwrap();
            if kind=="hello" {
                assert_eq!(request["payload"]["token"],token);
                write_frame(&writer,json!({"id":id,"ok":true,"payload":{}}));
            } else if kind=="test.barrier" {
                write_frame(&writer,json!({"id":id,"ok":true,"payload":{}}));
            } else if sender.send(ControlledRequest{kind:kind.into(),payload:request["payload"].clone(),id,writer:writer.clone()}).is_err() {break;}
        }
    });
    let bridge=RuntimeBridge::start(directory.clone());
    let writer=connected.recv_timeout(Duration::from_secs(3)).expect("bridge connected to controlled listener");
    (bridge,ControlledRuntime{requests,writer,directory,server:Some(server)})
}

impl ControlledRuntime {
    pub fn take(&self)->ControlledRequest {
        self.requests.recv_timeout(Duration::from_secs(3)).expect("expected runtime request")
    }
    pub fn try_take(&self)->Option<ControlledRequest> {self.requests.try_recv().ok()}
    pub fn take_with_timeout(&self,timeout:Duration)->Option<ControlledRequest> {self.requests.recv_timeout(timeout).ok()}

    /// A reply behind earlier replies lets the GPUI executor drain their updates.
    pub fn settle(&self,cx:&mut gpui::VisualTestContext,bridge:RuntimeBridge) {
        let complete=Arc::new(AtomicBool::new(false));
        let signal=complete.clone();
        cx.update(|window,cx|window.spawn(cx,async move |_|{
            bridge.request("test.barrier",json!({})).await.unwrap();
            signal.store(true,Ordering::Release);
        }).detach());
        let deadline=Instant::now()+Duration::from_secs(3);
        while !complete.load(Ordering::Acquire) {
            cx.run_until_parked();
            assert!(Instant::now()<deadline,"controlled response did not settle");
            std::thread::sleep(Duration::from_millis(1));
        }
        cx.run_until_parked();
    }
}

impl ControlledRequest {
    pub fn respond(self,value:Result<Value,String>) {
        let frame=match value {Ok(payload)=>json!({"id":self.id,"ok":true,"payload":payload}),Err(error)=>json!({"id":self.id,"ok":false,"error":error})};
        write_frame(&self.writer,frame);
    }
}

fn write_frame(writer:&Mutex<TcpStream>,frame:Value) {
    let mut stream=writer.lock().unwrap();
    let mut line=serde_json::to_vec(&frame).unwrap();line.push(b'\n');
    stream.write_all(&line).expect("controlled response write");
}

impl Drop for ControlledRuntime {
    fn drop(&mut self) {
        let _=self.writer.lock().unwrap().shutdown(Shutdown::Both);
        if let Some(server)=self.server.take() {let _=server.join();}
        let _=std::fs::remove_file(self.directory.join("host.json"));
        let _=std::fs::remove_dir(&self.directory);
    }
}

#[test]
fn controlled_runtime_barrier_round_trip_without_gpui_scheduler() {
    let (bridge,_server)=pair();
    let runtime=tokio::runtime::Runtime::new().unwrap();
    assert_eq!(runtime.block_on(bridge.request("test.barrier",json!({}))).unwrap(),json!({}));
}
