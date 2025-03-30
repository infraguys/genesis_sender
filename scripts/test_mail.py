#!/usr/bin/env python3

# Copyright 2025 Genesis Corporation
#
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

import smtplib, ssl

port = 587  # For SSL
user = input("Type your user name and press enter: ")
password = input("Type your password and press enter: ")
TO = input("Type recipient address and press enter: ")
FROM = "test@genesiscore.tech"
SUBJECT = "test email"
TEXT = "Hello, it's a test email from your Genesis Core installation!"

smtp = smtplib.SMTP("127.0.0.1", port="587")

smtp.ehlo()  # send the extended hello to our server
smtp.starttls()  # tell server we want to communicate with TLS encryption

smtp.login(user, password)  # login to our email server

# send our email message
smtp.sendmail("noreply@genesiscore.tech", TO, TEXT)

smtp.quit()  # finally, don't forget to close the connection

print("Success!")
