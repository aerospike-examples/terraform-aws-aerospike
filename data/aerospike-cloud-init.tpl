#cloud-config
---
fqdn: ${node_host}
manage_etc_hosts: true

write_files:
- content: |
    service {
        proto-fd-max 1024
        cluster-name aerospike-example
        node-id ${node_id}
    }

    logging {
        file /var/log/aerospike/aerospike.log {
            context any info
        }
    }

    network {
        service {
            address any
            port 3000
        }

        heartbeat {
            mode mesh
            port 3002
            mesh-seed-address-port ${seed_host} 3002
            interval 250
            timeout 10
        }

        fabric {
            port 3001
        }

        info {
            port 3003
        }
    }

    namespace test {
        replication-factor 2
        storage-engine memory {
            data-size 1G
        }
    }

  path: /etc/aerospike/aerospike.conf

runcmd:
 - [ systemctl, start, aerospike ]
