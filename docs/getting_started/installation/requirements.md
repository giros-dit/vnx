# Requirements

## System
- Modern Linux distribution (Ubuntu 14.04 or newer recommended)
- 2 Gb of RAM memory
- 10 Gb of disk space (depends mainly on the number of root-file-systems used)

## Virtualization
Processor with **virtualization support** (only needed if you use KVM virtual machines; not needed if you only use User-Mode-Linux or dynamips). You can check whether your processor has support for virtualization extensions using:

- **kvm-ok** command if available in your system:
```bash
# kvm-ok
INFO: Your CPU supports KVM extensions
INFO: /dev/kvm exists
KVM acceleration can be used
```

- Manually, executing the following command:
```bash
egrep '(vmx|svm)' --color=always /proc/cpuinfo
```

If you see the word vmx (for Intel processors) or svm (for AMD processors) in <span style="color:red">**red**</span></strong>, your processor has virtualization support. 

!!! attention
    Be aware that virtualization extensions are controled from the BIOS. Even if you see the vmx/svm flag you will have to access your BIOS setup and check that virtualization support is enabled. If you get the following error message:

    ```
    FATAL: Error inserting kvm_intel (...): Operation not supported
    ```

    It probably means that virtualization support is disabled in your BIOS setup.



