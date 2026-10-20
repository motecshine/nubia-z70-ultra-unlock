// SPDX-License-Identifier: BSD-3-Clause
// Minimal tool to reset a device that is stuck in Firehose mode (skip Sahara).
use anyhow::Result;
use qdl::types::{FirehoseConfiguration, FirehoseResetMode, FirehoseStorageType, QdlBackend, QdlDevice};
use qdl::{firehose_reset, setup_target_device};

fn main() -> Result<()> {
    let rw = setup_target_device(QdlBackend::Usb, None, None)?;

    let mut dev = QdlDevice {
        rw,
        fh_cfg: FirehoseConfiguration {
            storage_type: FirehoseStorageType::Ufs,
            backend: QdlBackend::Usb,
            ..Default::default()
        },
        reset_on_drop: false,
    };

    eprintln!("Sending firehose <power value=\"reset\"/> ...");
    // Reboot to normal system
    firehose_reset(&mut dev, &FirehoseResetMode::Reset, 0)?;
    eprintln!("Reset command sent.");
    Ok(())
}
