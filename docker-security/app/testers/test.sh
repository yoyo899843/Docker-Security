#!/bin/sh
# container capability / escape-surface probe
echo "===== $(hostname) ====="

echo "--- CapEff (raw) ---"
grep CapEff /proc/self/status

echo "--- CapEff (decoded) ---"
CAP=$(grep CapEff /proc/self/status | awk '{print $2}')
capsh --decode=0x$CAP 2>/dev/null || echo "capsh not installed"

echo "--- seccomp mode (2 = filtered, 0 = none) ---"
grep Seccomp /proc/self/status

echo "--- host block devices visible? ---"
ls /dev/sd* /dev/nvme* /dev/mapper/* 2>/dev/null || echo "none visible"

echo "--- can we mount? (try tmpfs) ---"
mkdir -p /tmp/mnt_test 2>/dev/null
if mount -t tmpfs none /tmp/mnt_test 2>/dev/null; then
  echo "MOUNT: OK"; umount /tmp/mnt_test
else
  echo "MOUNT: DENIED"
fi

echo "--- can we load a kernel module? (CAP_SYS_MODULE) ---"
if [ -r /proc/modules ] && echo "test" | insmod /dev/null 2>&1 | grep -qi "permitted\|denied"; then
  echo "INSMOD: DENIED (no CAP_SYS_MODULE)"
else
  # insmod against /dev/null always fails format-wise; check cap instead
  capsh --decode=0x$CAP 2>/dev/null | grep -q sys_module && echo "INSMOD: capability PRESENT" || echo "INSMOD: capability ABSENT"
fi

echo "--- can we access raw memory? (/dev/mem) ---"
if dd if=/dev/mem of=/dev/null bs=1 count=1 2>/dev/null; then
  echo "DEV_MEM: READABLE"
else
  echo "DEV_MEM: DENIED"
fi

echo "--- cgroup release_agent writable? (classic escape vector) ---"
if mount -t cgroup -o rdma cgroup /tmp/cg 2>/dev/null; then
  [ -w /tmp/cg/release_agent ] && echo "RELEASE_AGENT: WRITABLE (escape possible)" || echo "RELEASE_AGENT: present but not writable"
  umount /tmp/cg 2>/dev/null
else
  mkdir -p /tmp/cg 2>/dev/null
  if mount -t cgroup -o rdma cgroup /tmp/cg 2>/dev/null; then
    echo "RELEASE_AGENT: cgroup mount OK"
    umount /tmp/cg 2>/dev/null
  else
    echo "RELEASE_AGENT: cgroup mount DENIED (no SYS_ADMIN)"
  fi
fi

echo "--- host filesystem via bind ---"
ls /host/etc/hostname >/dev/null 2>&1 && echo "HOST BIND: readable (this is from the bind, NOT privileged)" || echo "HOST BIND: not mounted"

echo "===== end ====="