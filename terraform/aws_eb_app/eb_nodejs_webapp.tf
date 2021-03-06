variable "aws_region" {
  type        = string
  description = "The AWS Region"
  default     = "us-east-2"
}
variable "service_name" {
  type    = string
  default = "one"
}
variable "env_name" {
  type    = string
  default = "One-env"
}
variable "service_description" {
  type    = string
  default = "One"
}
variable "load_balancer_type" {
  type    = string
  default = "application"
}
variable "solution_stack" {
  type    = string
  default = "64bit Amazon Linux 2 v5.2.4 running Node.js 12"
}
variable "dns_domain" {
  type    = string
  default = "petrol-nt.net"
}

# pull in the dns zone
data "aws_route53_zone" "dns_zone" {
  name         = var.dns_domain
}

data "aws_elastic_beanstalk_hosted_zone" "current" {}

provider "aws" {
  region = var.aws_region
}


resource "aws_iam_role" "beanstalk_service_role" {
    name = "beanstalk-service-role"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "elasticbeanstalk.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "elasticbeanstalk"
        }
      }
    }
  ]
}
EOF
}

resource "aws_iam_role" "beanstalk_ec2_role" {
    name = "beanstalk-ec2-role"
    assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "beanstalk_service_profile" {
    name = "beanstalk-service-user"
    role = aws_iam_role.beanstalk_service_role.name
}

resource "aws_iam_instance_profile" "beanstalk_ec2_profile" {
    name = "beanstalk-ec2-user"
    role = aws_iam_role.beanstalk_ec2_role.name
}


resource "aws_iam_policy_attachment" "beanstalk_service_common" {
    name = "elastic-beanstalk-service"
    roles = [aws_iam_role.beanstalk_service_role.id]
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService"
}

resource "aws_iam_policy_attachment" "beanstalk_service_health" {
    name = "elastic-beanstalk-service-health"
    roles = [aws_iam_role.beanstalk_service_role.id]
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_policy_attachment" "beanstalk_ec2_worker" {
    name = "elastic-beanstalk-ec2-worker"
    roles = [aws_iam_role.beanstalk_ec2_role.id]
    policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_policy_attachment" "beanstalk_ec2_web" {
    name = "elastic-beanstalk-ec2-web"
    roles = [aws_iam_role.beanstalk_ec2_role.id]
    policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_policy_attachment" "beanstalk_ec2_container" {
    name = "elastic-beanstalk-ec2-container"
    roles = [aws_iam_role.beanstalk_ec2_role.id]
    policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

#Creating certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = format("%s%s%s", var.service_name, ".",  data.aws_route53_zone.dns_zone.name)
  validation_method = "DNS"
  tags = {
    Name = format("%s%s", var.service_name, " Terraform managed certificate")
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "dvo_record" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
      zone_id = data.aws_route53_zone.dns_zone.zone_id
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = each.value.zone_id
}

resource "aws_acm_certificate_validation" "cert_val" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.dvo_record : record.fqdn]
}

########

#Application and Environment

resource "aws_elastic_beanstalk_application" "nodejs-webapp" {
  name        = var.service_name
  description = var.service_description
}

resource "aws_elastic_beanstalk_environment" "eb-env" {
  name                = var.env_name
  application         = aws_elastic_beanstalk_application.nodejs-webapp.name
  solution_stack_name = var.solution_stack

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name = "LoadBalancerType"
    value = var.load_balancer_type
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name = "LoadBalancerIsShared"
    value = "false"
  }

  setting {
    namespace = "aws:elbv2:listener:default"
    name      = "Protocol"
    value     = "HTTPS"
  }
  
  setting {
    namespace = "aws:elbv2:listener:default"
    name      = "SSLCertificateArns"
    value     = aws_acm_certificate.cert.arn
  }

#  setting {
#    namespace = "aws:elbv2:loadbalancer"
#    name = "SecurityGroups"
#    value = aws_security_group.alb-sg.id
#  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = "vpc-096e5a7b58ad054e3"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = "subnet-01751847d52ca301f,subnet-09d9b29ed6883d131,subnet-0edf743bab2c8a797"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name = "AssociatePublicIpAddress"
    value = "true"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name = "ELBSubnets"
    value = "subnet-01751847d52ca301f,subnet-09d9b29ed6883d131,subnet-0edf743bab2c8a797"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name = "ELBScheme"
    value = "public"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name = "InstanceType"
    value = "t3.micro"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name = "Availability Zones"
    value = "Any 1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name = "MinSize"
    value = "1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name = "MaxSize"
    value = "1"
  }


  setting {
        namespace = "aws:elasticbeanstalk:environment"
        name      = "ServiceRole"
        value     = aws_iam_role.beanstalk_service_role.name
  }

  setting {
        namespace = "aws:autoscaling:launchconfiguration"
        name      = "IamInstanceProfile"
        value     = aws_iam_instance_profile.beanstalk_ec2_profile.name
  }

}

#DNS Alias
resource "aws_route53_record" "dns_alias" {
  zone_id = data.aws_route53_zone.dns_zone.zone_id
  name    = format("%s%s%s", var.service_name, ".",  data.aws_route53_zone.dns_zone.name)
  type    = "A"
  alias {
    name    = aws_elastic_beanstalk_environment.eb-env.cname
    zone_id = data.aws_elastic_beanstalk_hosted_zone.current.id
    evaluate_target_health = false
  }
}

#Configure Load balancer
#data "aws_lb" "selected" {
#  name = aws_elastic_beanstalk_environment.eb-env.load_balancers[0]
#}

#resource "aws_lb_listener" "https" {
#  load_balancer_arn = data.aws_lb.selected.arn
#  port              = "443"
#  protocol          = "HTTPS"
#  ssl_policy        = "ELBSecurityPolicy-2016-08"
#  certificate_arn   = aws_acm_certificate.cert.arn

#  default_action {
#    type             = "forward"
#    target_group_arn = data.aws_lb.selected.target_groups[0]
#  }
#}




output "resourse_dns_name" {
    value = aws_route53_record.dns_alias.name
    description = "Resourse FQDN"
}
