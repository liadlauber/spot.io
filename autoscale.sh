#!/bin/bash

#define varibles
SecurityGroup='sg-03419c2ca72f3754b'
ImageId='ami-05d72852800cbf29e'
InstanceType='t2.micro'
KeyPair='LiadKeyPair'
USER='ec2-user'
SubnetId='subnet-07c7524b'
KeyDir=sshkeys

#create load balancer
aws elb create-load-balancer \
--load-balancer-name my-load-balancer \
--listeners "Protocol=HTTP,LoadBalancerPort=80,InstanceProtocol=HTTP,InstancePort=80" \
--subnets $SubnetId \
--security-groups $SecurityGroup

#create launch configuration
aws autoscaling create-launch-configuration \
    --launch-configuration-name my-launch-config \
    --image-id $ImageId \
    --key-name $KeyPair \
    --instance-type $InstanceType \
    --instance-monitoring Enabled=true \
    --security-groups $SecurityGroup

#create autoscaling group
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name my-asg \
    --launch-configuration-name my-launch-config \
    --min-size 1 \
    --max-size 2 \
    --termination-policies "OldestInstance" \
    --load-balancer-names my-load-balancer \
    --vpc-zone-identifier $SubnetId

#define scaleup and scaledown autoscaling policies
SCALEUP=$(aws autoscaling put-scaling-policy \
--auto-scaling-group-name my-asg \
--policy-name scale-up \
--scaling-adjustment 1 \
--adjustment-type ChangeInCapacity \
--cooldown 120 | grep ARN | awk {'print $2'} | tr -d \",)

SCALEDOWN=$(aws autoscaling put-scaling-policy \
--auto-scaling-group-name my-asg \
--policy-name scale-down \
--scaling-adjustment -1 \
--adjustment-type ChangeInCapacity \
--cooldown 120 | grep ARN | awk {'print $2'} | tr -d \",)

#add another instance when cpu exceeds 80 percent
aws cloudwatch put-metric-alarm \
--alarm-name HighCpu \
--alarm-description "Alarm when CPU exceeds 80 percent" \
--metric-name CPUUtilization \
--namespace AWS/EC2 \
--statistic Average \
--period 60 \
--threshold 80 \
--comparison-operator GreaterThanThreshold  \
--dimensions "Name=AutoScalingGroupName,Value=my-asg" \
--evaluation-periods 1 \
--alarm-actions $SCALEUP \
--unit Percent

#remove one instance when cpu subcceeds 15 percent
aws cloudwatch put-metric-alarm \
--alarm-name LowCpu \
--alarm-description "Alarm when CPU succeeds 15 percent" \
--metric-name CPUUtilization \
--namespace AWS/EC2 \
--statistic Average \
--period 60 \
--threshold 15 \
--comparison-operator LessThanThreshold  \
--dimensions "Name=AutoScalingGroupName,Value=my-asg" \
--evaluation-periods 1 \
--alarm-actions $SCALEDOWN \
--unit Percent

sleep 60 #wait for instance to be Running

#get ec2 instance public ip for ssh use
PublicIP=$(aws ec2 describe-instances \
        --query 'Reservations[*].Instances[*].PublicIpAddress' --output text)

#simulate cpu spike in my ec2 instance
ssh -o StrictHostKeyChecking=no -i $KeyDir/$KeyPair.pem $USER@$PublicIP "sudo yum update -y; \
sudo amazon-linux-extras install epel -y; \
sudo yum install stress -y; \
stress --cpu 1 --timeout 180"

#now you can see another instance launching
#after 2 minutes one instace will be deleted 