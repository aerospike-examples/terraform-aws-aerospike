aws ec2-instance-connect ssh --connection-type direct --instance-id i-


aws ec2-instance-connect send-ssh-public-key --region us-west-2 --availability-zone us-west-2a --instance-id i-0ef18b69c18081276 --instance-os-user ec2-user --ssh-public-key file:///home/mcarrick/.ssh/id_rsa.pub

ssh -o "IdentitiesOnly=yes" -i /home/mcarrick/.ssh/id_rsa.pub ec2-user@ec2-34-217-149-209.us-west-2.compute.amazonaws.com

terraform apply -var 'aerospike_ami_owner=amazon' -var 'aerospike_ami_name=amzn2-ami-hvm*' -var 'aerospike_instance_root_volume_size=30'

terraform apply -var 'aerospike_ami_owner=amazon' -var 'aerospike_ami_name=al2023-ami-2023*' -var 'aerospike_instance_root_volume_size=30'

Instance connect endpoint takes a while

https://github.com/citrusleaf/cloud-image-build/blob/main/packer-template/amzn2023/amd64/sources.pkr.hcl#L6

I don't think this AMI is working.


The Aerospike AMI requires a specific `ami_id`. This is a deliberate design choice as it prevents accidental updates to all database nodes at the same time when AMIs are updated and it allows for a rolling update.

The `.internal` TLD might get accepted per https://www.icann.org/en/public-comment/proceeding/proposed-top-level-domain-string-for-private-use-24-01-2024

262212597706 is _our_ marketplace account
407670144475 is me