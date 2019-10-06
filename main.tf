# This terraform plan creates all resources required for Blue Prism
#---------------------------------------------
# AWS Security Group for Blue Prism Database #
#---------------------------------------------
resource "aws_security_group" "blueprism_db_sg_policy" {
  name        = var.db_sg_policy_name
  description = "Allow all inbound traffic from internal VPC"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    protocol  = "tcp"
    from_port = 1433
    to_port   = 1433
    cidr_blocks = split(
      ",",
      length(var.db_sg_ingress_cidr) > 0 ? join(",", var.db_sg_ingress_cidr) : data.aws_subnet.selected.cidr_block,
    )
  }

  tags = merge(
    var.tags,
    {
      "Name" = var.db_sg_policy_name
    },
  )
}

#----------------------------------
# AWS RDS Database for Blue Prism #
#----------------------------------
resource "aws_db_instance" "blueprism_db" {
  username = var.db_master_username
  password = var.db_master_password

  allocated_storage    = var.db_storage
  storage_type         = var.db_storage_type
  engine               = var.db_engine
  identifier           = var.db_identifier
  instance_class       = var.db_instance_class
  db_subnet_group_name = var.db_subnet_group_name
  timezone             = var.db_timezone

  final_snapshot_identifier  = "${var.db_identifier}-final-snapshot"
  auto_minor_version_upgrade = "true"
  apply_immediately          = var.db_changes_apply_immediately
  backup_retention_period    = var.db_backup_retention_period
  backup_window              = var.db_backup_window
  maintenance_window         = var.db_maintenance_window

  # This block should be used when changing size of the db instance server from t series to m series for scaling issues. Since on changing size it will destroy current db instance and save it's snapshot with the name given in final_snapshot_identifier. We can use it's id and pass it below to allow new instance be created from it's backup for smoother transition.
  snapshot_identifier = var.db_snapshot_identifier

  storage_encrypted = var.db_storage_encrypted == "true" ? "true" : ""
  kms_key_id        = var.db_storage_encrypted == "true" ? var.db_kms_key_id : ""

  deletion_protection = var.db_deletion_protection

  vpc_security_group_ids = [aws_security_group.blueprism_db_sg_policy.id]

  tags = merge(
    var.tags,
    {
      "Name" = "blueprism-db"
    },
  )

  depends_on = [aws_security_group.blueprism_db_sg_policy]
}

#-----------------------------------
# AWS EC2 AppServer for Blue Prism #
#-----------------------------------
resource "aws_instance" "blueprism_appserver" {
  count = length(var.appserver_private_ip)

  ami           = data.aws_ami.appserver_ami.id
  instance_type = var.appserver_instance_type

  key_name                = var.appserver_key_name
  disable_api_termination = var.appserver_disable_api_termination

  root_block_device {
    volume_size = var.appserver_root_volume_size
  }

  volume_tags = {
    Name = "blueprism-appserver-root-${count.index}"
  }

  private_ip             = element(var.appserver_private_ip, count.index)
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.blueprism_appserver_sg.id]

  tags = merge(
    var.tags,
    {
      "Name" = "blueprism-appserver-${count.index}"
    },
  )

  user_data = data.template_file.blueprism_appserver_setup[count.index].rendered

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [
    aws_db_instance.blueprism_db,
    aws_security_group.blueprism_appserver_sg,
  ]
}

#----------------------------------------------
# AWS Security Group for Blue Prism Appserver #
#----------------------------------------------
resource "aws_security_group" "blueprism_appserver_sg" {
  name        = "blueprism-appserver-sg"
  description = "This is the security group policy for Blue Prism AppServer"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.appserver_sg_ingress_cidr
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      "Name" = "blueprism-appserver-sg"
    },
  )
}

#--------------------------------------------
# AWS EC2 Interactive Client for Blue Prism #
#--------------------------------------------
resource "aws_instance" "blueprism_client" {
  count = length(var.client_private_ip)

  ami           = data.aws_ami.client_ami.id
  instance_type = var.client_instance_type

  key_name                = var.client_key_name
  disable_api_termination = var.client_disable_api_termination

  root_block_device {
    volume_size = var.client_root_volume_size
  }

  volume_tags = {
    Name = "blueprism-client-root-${count.index}"
  }

  private_ip             = element(var.client_private_ip, count.index)
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.blueprism_client_sg.id]

  tags = merge(
    var.tags,
    {
      "Name" = "blueprism-client-${count.index}"
    },
  )

  user_data = data.template_file.blueprism_client_setup[count.index].rendered

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_security_group.blueprism_client_sg]
}

#-------------------------------------------------------
# AWS Security Group for Blue Prism Interactive Client #
#-------------------------------------------------------
resource "aws_security_group" "blueprism_client_sg" {
  name        = "blueprism-client-sg"
  description = "This is the security group policy for Blue Prism Interactive Client"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.client_sg_ingress_cidr
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      "Name" = "blueprism-client-sg"
    },
  )
}

#-------------------------------------
# AWS EC2 Resource PC for Blue Prism #
#-------------------------------------
resource "aws_instance" "blueprism_resource" {
  count = length(var.resource_private_ip)

  ami           = data.aws_ami.resource_ami.id
  instance_type = var.resource_instance_type

  key_name                = var.resource_key_name
  disable_api_termination = var.resource_disable_api_termination

  root_block_device {
    volume_size = var.resource_root_volume_size
  }

  volume_tags = {
    Name = "blueprism-resource-root-${count.index}"
  }

  private_ip             = element(var.resource_private_ip, count.index)
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.blueprism_resource_sg.id]

  tags = merge(
    var.tags,
    {
      "Name" = "blueprism-resource-${count.index}"
    },
  )

  user_data = data.template_file.blueprism_resource_setup[count.index].rendered

  lifecycle {
    ignore_changes = [ami]
  }

  depends_on = [aws_security_group.blueprism_resource_sg]
}

#------------------------------------------------
# AWS Security Group for Blue Prism Resource PC #
#------------------------------------------------
resource "aws_security_group" "blueprism_resource_sg" {
  name        = "blueprism-resource-sg"
  description = "This is the security group policy for Blue Prism Resource PC"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.resource_sg_ingress_cidr
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      "Name" = "blueprism-resource-sg"
    },
  )
}

