/**
 * code based of test1.c 
 *
 * A simple test of kernel module. 
 * 
 * To compile, run makefile by entering "make"
 *
 */

#include <linux/init.h>
#include <linux/module.h>
#include <linux/kernel.h>

/* This function is called when the module is loaded. */
static int test1_init(void)
{
       // please reference to the Tutorial 1 to add the printk command:
       printk(KERN_INFO "Loading Module\n");     // printk: kernel printf
       return 0;
}

/* This function is called when the module is removed. */
static void test1_exit(void) 
{
	// please reference to the Tutorial 1 to add the printk command:
       printk(KERN_INFO "Removing Module\n");    // printk: kernel printf
}

/* Macros for registering module entry and exit points. */
module_init( test1_init );
module_exit( test1_exit );

MODULE_LICENSE("GPL");

// please reference to the Tutorial 1 to add the module description:
MODULE_DESCRIPTION("Test1 Module");

// please reference to the Tutorial 1 to add the module author:
MODULE_AUTHOR("CSC1107");

