OVS-DPDK
========

Run these two script according to their index in order to deploy OVS with DPDK
support.

Configuration
-------------

The default configuration of the neutron chart must be adapted according to the
underlying hardware. The corresponding configuration parameter is labled with
"CHANGE-ME" in the script "160-compute-kit.sh". Specifically, the "ovs_dpdk"
configuration section should list all NICs which should be bound to DPDK with
their corresponding PCI-IDs. Moreover, the name of each NIC needs to be unique,
e.g., dpdk0, dpdk1::

  ovs_dpdk:
    enabled: true
    driver: uio_pci_generic
    nics:
      - name: dpdk0
        # CHANGE-ME: modify pci_id according to hardware
        pci_id: '0000:05:00.0'
        bridge: br-phy
        migrate_ip: true
    bridges:
      - name: br-phy
