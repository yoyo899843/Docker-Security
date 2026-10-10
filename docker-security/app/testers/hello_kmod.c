#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("harmless proof that a privileged container can run code in the host kernel");

static int __init hello_init(void)
{
    printk(KERN_INFO "[container_escape_demo] hello from inside the HOST kernel — loaded by a container\n");
    return 0;
}

static void __exit hello_exit(void)
{
    printk(KERN_INFO "[container_escape_demo] goodbye — module unloaded\n");
}

module_init(hello_init);
module_exit(hello_exit);