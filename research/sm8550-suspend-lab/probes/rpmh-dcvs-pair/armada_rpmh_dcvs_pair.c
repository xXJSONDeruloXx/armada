// SPDX-License-Identifier: GPL-2.0-only
#include <linux/device/bus.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <soc/qcom/cmd-db.h>
#include <soc/qcom/rpmh.h>
#include <soc/qcom/tcs.h>

#define APPS_RSC_CLIENT "17a00000.rsc:regulators-0"

static int __init armada_rpmh_dcvs_pair_init(void)
{
	struct tcs_cmd cmds[2] = {};
	struct device *dev;
	int ret;

	dev = bus_find_device_by_name(&platform_bus_type, NULL, APPS_RSC_CLIENT);
	if (!dev) {
		pr_err("SLEEP_AB: missing Apps RSC client %s\n", APPS_RSC_CLIENT);
		return -ENODEV;
	}

	cmds[0].addr = cmd_db_read_addr("MC4");
	cmds[1].addr = cmd_db_read_addr("SH5");
	if (!cmds[0].addr || !cmds[1].addr) {
		dev_err(dev, "SLEEP_AB: CMD-DB lookup failed\n");
		ret = -ENODEV;
		goto out;
	}

	cmds[0].data = cmds[1].data = BCM_TCS_CMD(1, 1, 0, 0);
	ret = rpmh_write_async(dev, RPMH_SLEEP_STATE, cmds, ARRAY_SIZE(cmds));
	if (ret) {
		dev_err(dev, "SLEEP_AB: SLEEP request failed: %d\n", ret);
		goto out;
	}

	cmds[0].data = cmds[1].data = BCM_TCS_CMD(1, 1, 0, 1);
	ret = rpmh_write_async(dev, RPMH_WAKE_ONLY_STATE, cmds, ARRAY_SIZE(cmds));
	if (ret)
		dev_err(dev, "SLEEP_AB: WAKE_ONLY request failed: %d\n", ret);
	else
		dev_info(dev, "SLEEP_AB: MC4=%#x SH5=%#x SLEEP=0 WAKE_ONLY=1\n",
			 cmds[0].addr, cmds[1].addr);
out:
	put_device(dev);
	return ret;
}

static void __exit armada_rpmh_dcvs_pair_exit(void)
{
	pr_info("RPMh request cache persists until reboot\n");
}

module_init(armada_rpmh_dcvs_pair_init);
module_exit(armada_rpmh_dcvs_pair_exit);
MODULE_DESCRIPTION("Temporary Armada SM8550 MC4/SH5 sleep-pair probe");
MODULE_LICENSE("GPL");
