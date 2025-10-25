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
    
    # Sort credentials by student number
    def get_student_number(cred):
        student_name = cred.get('student_name', 'Student-0')
        return int(student_name.split('-')[1])
    
    sorted_credentials = sorted(credentials, key=get_student_number)
    
    message_parts = ["EC2 Instance Login Instructions - All Students\n"]
    
    for i, cred in enumerate(sorted_credentials, 1):
        message_parts.append(f"""
=== STUDENT {i}: {cred.get('student_name', f'Student {i}')} ===

AWS Console Access:
Console URL: https://248189947068.signin.aws.amazon.com/console
Username: chatbot-student-{i}
Password: {cred.get('console_password', 'N/A')}

AWS CLI Access:
Username: chatbot-student-{i}
Access Key ID: {cred.get('cli_access_key', 'N/A')}
Secret Access Key: {cred.get('cli_secret_key', 'N/A')}
""")
    
    message_parts.append("\nNote: Teacher has full EC2 access permissions.")
    full_message = "".join(message_parts)
    
    sns.publish(
        TopicArn=topic_arn,
        Message=full_message,
        Subject=f"Login Instructions - All {len(sorted_credentials)} Students"
    )

if __name__ == "__main__":
    credentials = get_credentials_from_dynamodb()
    send_login_instructions(credentials)
    print(f"Sent login instructions for {len(credentials)} students")
