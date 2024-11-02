use bluer::{
    adv::Advertisement,
    gatt::local::{
        Application, Characteristic, CharacteristicNotifier, CharacteristicNotify,
        CharacteristicNotifyMethod, CharacteristicWrite, CharacteristicWriteMethod, Service,
    },
    Uuid,
};
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use std::{
    fs,
    process::Command,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::sync::broadcast;
use tokio::time::sleep;
use tokio_stream::wrappers::BroadcastStream;

// Constants for Service and Characteristic UUIDs
const WIFI_SERVICE_UUID: Uuid = Uuid::from_u128(0x05dfab8e_41fe_4d81_a06d_2a274bdf1a66);
const CREDENTIALS_CHAR_UUID: Uuid = Uuid::from_u128(0x33e6512c_86d6_470c_99c1_35333f170237);
const STATUS_CHAR_UUID: Uuid = Uuid::from_u128(0x5b318560_1fb5_43b7_a1a6_a28a0990cd84);

#[derive(Debug, Serialize, Deserialize)]
struct WiFiCredentials {
    ssid: String,
    password: String,
}

#[derive(Debug, Clone)]
enum WiFiStatus {
    Ready,
    Connecting,
    Connected,
    Failed,
    Error(String),
}

impl ToString for WiFiStatus {
    fn to_string(&self) -> String {
        match self {
            WiFiStatus::Ready => "READY".into(),
            WiFiStatus::Connecting => "CONNECTING".into(),
            WiFiStatus::Connected => "CONNECTED".into(),
            WiFiStatus::Failed => "FAILED".into(),
            WiFiStatus::Error(msg) => format!("ERROR: {}", msg),
        }
    }
}

struct WiFiManager {
    status: Arc<Mutex<WiFiStatus>>,
    status_tx: broadcast::Sender<Vec<u8>>,
}

impl WiFiManager {
    fn new() -> Self {
        let (status_tx, _) = broadcast::channel(16);
        Self {
            status: Arc::new(Mutex::new(WiFiStatus::Ready)),
            status_tx,
        }
    }

    async fn configure_wifi(&self, credentials: WiFiCredentials) -> bool {
        self.update_status(WiFiStatus::Connecting).await;

        let config = format!(
            r#"country=US
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={{
    ssid="{}"
    psk="{}"
    key_mgmt=WPA-PSK
}}"#,
            credentials.ssid, credentials.password
        );

        match fs::write("/etc/wpa_supplicant/wpa_supplicant.conf", config) {
            Ok(_) => (),
            Err(e) => {
                self.update_status(WiFiStatus::Error(e.to_string())).await;
                return false;
            }
        }

        match Command::new("sudo")
            .args(["wpa_cli", "-i", "wlan0", "reconfigure"])
            .status()
        {
            Ok(_) => (),
            Err(e) => {
                self.update_status(WiFiStatus::Error(e.to_string())).await;
                return false;
            }
        }

        sleep(Duration::from_secs(5)).await;

        match Command::new("iwgetid").output() {
            Ok(output) => {
                let connected = String::from_utf8_lossy(&output.stdout).contains(&credentials.ssid);
                self.update_status(if connected {
                    WiFiStatus::Connected
                } else {
                    WiFiStatus::Failed
                })
                .await;
                connected
            }
            Err(e) => {
                self.update_status(WiFiStatus::Error(e.to_string())).await;
                false
            }
        }
    }

    async fn update_status(&self, status: WiFiStatus) {
        let mut current = self.status.lock().unwrap();
        *current = status.clone();
        let _ = self.status_tx.send(status.to_string().into_bytes());
    }
}

#[tokio::main]
async fn main() -> bluer::Result<()> {
    let session = bluer::Session::new().await?;
    let adapter = session.default_adapter().await?;

    if !adapter.is_powered().await? {
        adapter.set_powered(true).await?;
    }

    println!("Bluetooth adapter {} is ready", adapter.name());

    let wifi_manager = Arc::new(WiFiManager::new());
    let manager_clone = wifi_manager.clone();

    let app = Application {
        services: vec![Service {
            uuid: WIFI_SERVICE_UUID,
            primary: true,
            characteristics: vec![
                Characteristic {
                    uuid: CREDENTIALS_CHAR_UUID,
                    write: Some(CharacteristicWrite {
                        write: true,
                        // write_without_response: false,
                        // encrypt_authenticated_write: false,
                        // authenticated_signed_writes: false,
                        // reliable_write: false,
                        secure_write: false,
                        encrypt_write: false,
                        method: CharacteristicWriteMethod::Fun(Box::new(
                            move |write_value, req| {
                                println!("Write request {:?} with value {:x?}", &req, &write_value);
                                let manager = manager_clone.clone();

                                Box::pin(async move {
                                    match serde_json::from_slice::<WiFiCredentials>(&write_value) {
                                        Ok(credentials) => {
                                            manager.configure_wifi(credentials).await;
                                            Ok(())
                                        }
                                        Err(e) => {
                                            manager
                                                .update_status(WiFiStatus::Error(e.to_string()))
                                                .await;
                                            Ok(())
                                        }
                                    }
                                })
                            },
                        )),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
                // Status characteristic (notify)
                Characteristic {
                    uuid: STATUS_CHAR_UUID,
                    notify: Some(CharacteristicNotify {
                        notify: true,
                        // indicate: true,
                        // authentication_required: false,
                        // authorization_required: false,
                        method: CharacteristicNotifyMethod::Fun(Box::new(
                            move |mut notifier: CharacteristicNotifier| {
                                let rx = wifi_manager.status_tx.subscribe();
                                Box::pin(async move {
                                    let mut stream = BroadcastStream::new(rx);
                                    while let Ok(Some(value)) = stream.next().await.transpose() {
                                        if let Err(e) = notifier.notify(value).await {
                                            eprintln!("Failed to send notification: {}", e);
                                            break;
                                        }
                                    }
                                })
                            },
                        )),
                        ..Default::default()
                    }),
                    ..Default::default()
                },
            ],
            ..Default::default()
        }],
        ..Default::default()
    };

    adapter.serve_gatt_application(app).await?;

    let le_advertisement = Advertisement {
        service_uuids: vec![WIFI_SERVICE_UUID].into_iter().collect(),
        discoverable: Some(true),
        local_name: Some("WiFi Setup".to_string()),
        ..Default::default()
    };

    let _handle = adapter.advertise(le_advertisement).await?;
    println!("Advertising WiFi configuration service...");

    // Keep the application running
    loop {
        sleep(Duration::from_secs(1)).await;
    }

    // The handle will be dropped when the main function ends
    #[allow(unreachable_code)]
    {
        drop(_handle);
        Ok(())
    }
}
