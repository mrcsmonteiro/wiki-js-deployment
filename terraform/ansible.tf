resource "null_resource" "ansible_provisioning" {
  # This makes the null_resource wait for the EC2 instance to be created
  depends_on = [
    aws_instance.wikijs_server
  ]

  # triggers block to re-run the provisioner upon code changes
  triggers = {
    # Generate a hash of all Ansible playbook files in the directory
    # This ensures a change in ANY file will trigger a re-run
    ansible_content_hash = sha1(join("", [
      for f in fileset("../ansible", "**/*.yml") : file("../ansible/${f}")
    ]))
  }

  # This provisioner will run the ansible-playbook command locally
  provisioner "local-exec" {
    working_dir = "../ansible"
    command     = "ansible-playbook playbook.yml"
  }
}