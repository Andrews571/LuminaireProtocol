#!/usr/bin/env python3
"""
Re:Kernel source injector for android14-6.1-lts.

Injects a Netlink server into three kernel files:
  - drivers/android/rekernel.h     (new file — Netlink server impl)
  - drivers/android/binder.c       (binder_transaction hooks)
  - drivers/android/binder_alloc.c (async buffer full hook)
  - kernel/signal.c                (signal hook)

Idempotent: checks for marker before injecting.
"""

import sys
import os

KERNEL_SRC = sys.argv[1] if len(sys.argv) > 1 else "."

REKERNEL_HEADER = """\
/* SPDX-License-Identifier: GPL-2.0 */
/* Re:Kernel — Netlink server for binder/signal event reporting.
 * Integrated by LuminaireProtocol. Source: Sakion-Team/Re-Kernel
 */
#ifndef _REKERNEL_H
#define _REKERNEL_H

#include <linux/init.h>
#include <linux/types.h>
#include <net/sock.h>
#include <linux/netlink.h>
#include <linux/proc_fs.h>
#include <linux/freezer.h>
#include <linux/sched/jobctl.h>

#define NETLINK_REKERNEL_MAX    26
#define NETLINK_REKERNEL_MIN    22
#define USER_PORT               100
#define PACKET_SIZE             128
#define MIN_USERAPP_UID         (10000)
#define MAX_SYSTEM_UID          (2000)
#define RESERVE_ORDER           17
#define WARN_AHEAD_SPACE        (1 << RESERVE_ORDER)

static struct sock *rekernel_netlink;
extern struct net init_net;
static int netlink_unit = NETLINK_REKERNEL_MIN;

static inline bool line_is_frozen(struct task_struct *task)
{
	return frozen(task->group_leader) || freezing(task->group_leader);
}

static int send_netlink_message(char *msg, uint16_t len)
{
	struct sk_buff *skbuffer;
	struct nlmsghdr *nlhdr;

	skbuffer = nlmsg_new(len, GFP_ATOMIC);
	if (!skbuffer) {
		printk("rekernel: nlmsg_new failed\\n");
		return -1;
	}
	nlhdr = nlmsg_put(skbuffer, 0, 0, netlink_unit, len, 0);
	if (!nlhdr) {
		printk("rekernel: nlmsg_put failed\\n");
		nlmsg_free(skbuffer);
		return -1;
	}
	memcpy(nlmsg_data(nlhdr), msg, len);
	return netlink_unicast(rekernel_netlink, skbuffer, USER_PORT,
			       MSG_DONTWAIT);
}

static void netlink_rcv_msg(struct sk_buff *skbuffer) {}

static struct netlink_kernel_cfg rekernel_cfg = {
	.input = netlink_rcv_msg,
};

static int rekernel_unit_show(struct seq_file *m, void *v)
{
	seq_printf(m, "%d\\n", netlink_unit);
	return 0;
}

static int rekernel_unit_open(struct inode *inode, struct file *file)
{
	return single_open(file, rekernel_unit_show, NULL);
}

static const struct file_operations rekernel_unit_fops = {
	.open    = rekernel_unit_open,
	.read    = seq_read,
	.llseek  = seq_lseek,
	.release = single_release,
	.owner   = THIS_MODULE,
};

static struct proc_dir_entry *rekernel_dir, *rekernel_unit_entry;

static int start_rekernel_server(void)
{
	if (rekernel_netlink != NULL)
		return 0;
	for (netlink_unit = NETLINK_REKERNEL_MIN;
	     netlink_unit < NETLINK_REKERNEL_MAX; netlink_unit++) {
		rekernel_netlink = (struct sock *)netlink_kernel_create(
			&init_net, netlink_unit, &rekernel_cfg);
		if (rekernel_netlink != NULL)
			break;
	}
	if (rekernel_netlink == NULL) {
		printk("rekernel: failed to create netlink server!\\n");
		return -1;
	}
	printk("rekernel: netlink server created, unit=%d\\n", netlink_unit);
	rekernel_dir = proc_mkdir("rekernel", NULL);
	if (!rekernel_dir) {
		printk("rekernel: create /proc/rekernel failed\\n");
	} else {
		char buff[32];

		sprintf(buff, "%d", netlink_unit);
		rekernel_unit_entry = proc_create(buff, 0644, rekernel_dir,
						  &rekernel_unit_fops);
		if (!rekernel_unit_entry)
			printk("rekernel: create unit procfs entry failed\\n");
	}
	return 0;
}

#endif /* _REKERNEL_H */
"""

BINDER_REPLY_HOOK = """\
\t\t/* Re:Kernel: notify on reply to frozen system proc */
\t\tif (start_rekernel_server() == 0) {
\t\t\tif (target_proc
\t\t\t\t&& target_proc->tsk != NULL
\t\t\t\t&& proc->tsk != NULL
\t\t\t\t&& task_uid(target_proc->tsk).val <= MAX_SYSTEM_UID
\t\t\t\t&& proc->pid != target_proc->pid
\t\t\t\t&& line_is_frozen(target_proc->tsk)) {
\t\t\t\tchar binder_kmsg[PACKET_SIZE];

\t\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg),
\t\t\t\t\t"type=Binder,bindertype=reply,oneway=0,"
\t\t\t\t\t"from_pid=%d,from=%d,target_pid=%d,target=%d;",
\t\t\t\t\tproc->pid, task_uid(proc->tsk).val,
\t\t\t\t\ttarget_proc->pid,
\t\t\t\t\ttask_uid(target_proc->tsk).val);
\t\t\t\tsend_netlink_message(binder_kmsg,
\t\t\t\t\t\t     strlen(binder_kmsg));
\t\t\t}
\t\t}
\t\t/* Re:Kernel end */
"""

BINDER_TXN_HOOK = """\
\t\t/* Re:Kernel: notify on transaction to frozen user app */
\t\tif (start_rekernel_server() == 0) {
\t\t\tif (target_proc
\t\t\t\t&& target_proc->tsk != NULL
\t\t\t\t&& proc->tsk != NULL
\t\t\t\t&& task_uid(target_proc->tsk).val > MIN_USERAPP_UID
\t\t\t\t&& proc->pid != target_proc->pid
\t\t\t\t&& line_is_frozen(target_proc->tsk)) {
\t\t\t\tchar binder_kmsg[PACKET_SIZE];

\t\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg),
\t\t\t\t\t"type=Binder,bindertype=transaction,"
\t\t\t\t\t"oneway=%d,from_pid=%d,from=%d,"
\t\t\t\t\t"target_pid=%d,target=%d;",
\t\t\t\t\ttr->flags & TF_ONE_WAY,
\t\t\t\t\tproc->pid, task_uid(proc->tsk).val,
\t\t\t\t\ttarget_proc->pid,
\t\t\t\t\ttask_uid(target_proc->tsk).val);
\t\t\t\tsend_netlink_message(binder_kmsg,
\t\t\t\t\t\t     strlen(binder_kmsg));
\t\t\t}
\t\t}
\t\t/* Re:Kernel end */
"""

BINDER_ALLOC_HOOK = """\
\t/* Re:Kernel: notify on async buffer full for frozen proc */
\tif (is_async
\t    && (alloc->free_async_space <
\t\t3 * (size + sizeof(struct binder_buffer))
\t        || alloc->free_async_space < WARN_AHEAD_SPACE)) {
\t\tstruct task_struct *proc_task = NULL;

\t\trcu_read_lock();
\t\tproc_task = find_task_by_vpid(alloc->pid);
\t\trcu_read_unlock();
\t\tif (proc_task != NULL && start_rekernel_server() == 0) {
\t\t\tif (line_is_frozen(proc_task)) {
\t\t\t\tchar binder_kmsg[PACKET_SIZE];

\t\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg),
\t\t\t\t\t"type=Binder,bindertype=free_buffer_full,"
\t\t\t\t\t"oneway=1,from_pid=%d,from=%d,"
\t\t\t\t\t"target_pid=%d,target=%d;",
\t\t\t\t\tcurrent->pid, task_uid(current).val,
\t\t\t\t\tproc_task->pid,
\t\t\t\t\ttask_uid(proc_task).val);
\t\t\t\tsend_netlink_message(binder_kmsg,
\t\t\t\t\t\t     strlen(binder_kmsg));
\t\t\t}
\t\t}
\t}
\t/* Re:Kernel end */
"""

SIGNAL_HOOK = """\
\t/* Re:Kernel: notify on kill signal to frozen proc */
\tif (start_rekernel_server() == 0) {
\t\tif (line_is_frozen(current)
\t\t    && (sig == SIGKILL || sig == SIGTERM
\t\t\t|| sig == SIGABRT || sig == SIGQUIT)) {
\t\t\tchar binder_kmsg[PACKET_SIZE];

\t\t\tsnprintf(binder_kmsg, sizeof(binder_kmsg),
\t\t\t\t"type=Signal,signal=%d,killer_pid=%d,"
\t\t\t\t"killer=%d,dst_pid=%d,dst=%d;",
\t\t\t\tsig, task_tgid_nr(p), task_uid(p).val,
\t\t\t\ttask_tgid_nr(current),
\t\t\t\ttask_uid(current).val);
\t\t\tsend_netlink_message(binder_kmsg,
\t\t\t\t\t     strlen(binder_kmsg));
\t\t}
\t}
\t/* Re:Kernel end */
"""

MARKER = "Re:Kernel"


def read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def already_patched(content):
    return MARKER in content


def inject_after(content, anchor, injection, label):
    if anchor not in content:
        print(f"  [WARN] anchor not found for {label}, skipping")
        return content, False
    idx = content.index(anchor) + len(anchor)
    return content[:idx] + "\n" + injection + content[idx:], True


def patch_binder_c(src):
    path = os.path.join(src, "drivers", "android", "binder.c")
    content = read(path)

    if already_patched(content):
        print("  binder.c: already patched, skipping")
        return

    include_anchor = '#include "binder_alloc.h"'
    content, ok1 = inject_after(
        content,
        include_anchor,
        '#include "rekernel.h"\n',
        "binder.c include"
    )

    reply_anchor = (
        "\t\ttarget_proc = target_thread->proc;\n"
        "\t\ttarget_proc->tmp_ref++;\n"
        "\t\tbinder_inner_proc_unlock(target_thread->proc);\n"
    )
    content, ok2 = inject_after(
        content, reply_anchor, BINDER_REPLY_HOOK, "binder reply hook"
    )

    txn_anchor = "\t\te->to_node = target_node->debug_id;\n"
    content, ok3 = inject_after(
        content, txn_anchor, BINDER_TXN_HOOK, "binder txn hook"
    )

    if ok1 or ok2 or ok3:
        write(path, content)
        print("  binder.c: patched ✅")
    else:
        print("  binder.c: no anchors matched, skipping")


def patch_binder_alloc_c(src):
    path = os.path.join(src, "drivers", "android", "binder_alloc.c")
    content = read(path)

    if already_patched(content):
        print("  binder_alloc.c: already patched, skipping")
        return

    include_anchor = "#include <linux/shrinker.h>"
    if include_anchor not in content:
        include_anchor = "#include <linux/slab.h>"
    content, _ = inject_after(
        content,
        include_anchor,
        '#include "rekernel.h"\n',
        "binder_alloc.c include"
    )

    alloc_anchor = (
        "\tif (is_async &&\n"
        "\t    alloc->free_async_space < size + sizeof(struct binder_buffer)) {\n"
    )
    content, ok = inject_after(
        content, alloc_anchor, BINDER_ALLOC_HOOK, "binder_alloc hook"
    )

    if ok:
        write(path, content)
        print("  binder_alloc.c: patched ✅")
    else:
        print("  binder_alloc.c: anchor not found, skipping")


def patch_signal_c(src):
    path = os.path.join(src, "kernel", "signal.c")
    content = read(path)

    if already_patched(content):
        print("  signal.c: already patched, skipping")
        return

    include_anchor = "#include <linux/freezer.h>"
    if include_anchor not in content:
        include_anchor = "#include <linux/posix-timers.h>"
    content, _ = inject_after(
        content,
        include_anchor,
        '#include "../drivers/android/rekernel.h"\n',
        "signal.c include"
    )

    signal_anchor = (
        "\tif (lock_task_sighand(p, &flags)) {\n"
        "\t\tret = send_signal(sig, info, p, group);\n"
        "\t\tunlock_task_sighand(p, &flags);\n"
        "\t}\n"
    )
    content, ok = inject_after(
        content, signal_anchor, SIGNAL_HOOK, "signal hook"
    )

    if ok:
        write(path, content)
        print("  signal.c: patched ✅")
    else:
        print("  signal.c: anchor not found, skipping")


def write_header(src):
    path = os.path.join(src, "drivers", "android", "rekernel.h")
    if os.path.exists(path):
        print("  rekernel.h: already exists, skipping")
        return
    write(path, REKERNEL_HEADER)
    print("  rekernel.h: created ✅")


def main():
    print(f"Re:Kernel injector — kernel src: {KERNEL_SRC}")
    write_header(KERNEL_SRC)
    patch_binder_c(KERNEL_SRC)
    patch_binder_alloc_c(KERNEL_SRC)
    patch_signal_c(KERNEL_SRC)
    print("Re:Kernel injection complete ✅")


if __name__ == "__main__":
    main()
