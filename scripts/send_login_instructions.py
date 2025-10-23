#!/usr/bin/env python3

import boto3
import json

def get_credentials_from_dynamodb():
    dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
    table = dynamodb.Table('student-credentials')
    
    response = table.scan()
    return response['Items']

def send_login_instructions(credentials):
    sns = boto3.client('sns', region_name='us-east-1')
    topic_arn = 'arn:aws:sns:us-east-1:248189947068:dataiesb-chatbot'
    
    for cred in credentials:
        message = f"""
EC2 Instance Login Instructions - {cred.get('student_name', 'Student')}

=== SSH Access ===
Instance ID: {cred.get('instance_id', 'N/A')}
Username: {cred.get('username', 'N/A')}
Password: {cred.get('password', 'N/A')}
Public IP: {cred.get('public_ip', 'N/A')}

SSH Command:
ssh {cred.get('username', 'ec2-user')}@{cred.get('public_ip', 'IP_ADDRESS')}

=== AWS CLI Access ===
Access Key ID: {cred.get('cli_access_key', 'N/A')}
Secret Access Key: {cred.get('cli_secret_key', 'N/A')}

CLI Configuration:
aws configure set aws_access_key_id {cred.get('cli_access_key', 'ACCESS_KEY')}
aws configure set aws_secret_access_key {cred.get('cli_secret_key', 'SECRET_KEY')}
aws configure set default.region us-east-1

=== AWS Console Access ===
Login URL: {cred.get('login_url', 'https://console.aws.amazon.com/')}

Note: Teacher has full EC2 access permissions.
"""
        
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=f"Login Instructions - {cred.get('student_name', 'Student')}"
        )

if __name__ == "__main__":
    credentials = get_credentials_from_dynamodb()
    send_login_instructions(credentials)
    print(f"Sent login instructions for {len(credentials)} students")
