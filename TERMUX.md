# Full Throttle N64 r2r — Termux diagnostics

Apply the r2r update using the standalone update bundle. It accepts either the
known failed-r2o repository or the exact r2q repository as its live baseline,
and refuses anything else.

After GitHub Actions builds `full-throttle-n64-r2r.z64`, put that ROM on the
SummerCart and start the USB capture before launching it:

```bash
bash ~/full-throttle-n64-r2r-push/scripts/record_sc64_log.sh
```

For a listener that requires an explicit USB device:

```bash
bash ~/full-throttle-n64-r2r-push/scripts/record_sc64_log.sh /dev/bus/usb/001/002
```

The script uses the existing listener at:

```text
~/sc64-termux-log/sc64-listen
```

and writes timestamped captures to:

```text
~/storage/downloads/ft64-sc64-YYYYMMDD-HHMMSS.log
```

Let the retail intro finish, leave the black screen visible for about 3-5
seconds, then press Ctrl+C and upload that log.
