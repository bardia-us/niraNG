"""Optional visual QR round-trip for generated test fixtures; requires OpenCV."""
import sys
from urllib.parse import urlsplit, parse_qs
import cv2

image = cv2.imread(sys.argv[1])
decoded, points, _ = cv2.QRCodeDetector().detectAndDecode(image)
if points is None or not decoded:
    raise SystemExit('Local fixture QR was not decodable')
uri = urlsplit(decoded)
values = parse_qs(uri.query)
if uri.scheme != 'otpauth' or uri.netloc != 'totp' or values.get('secret') != [sys.argv[2]]:
    raise SystemExit('QR did not round-trip the fixture authenticator secret')
if values.get('period', ['30']) != ['30'] or values.get('digits', ['6']) != ['6']:
    raise SystemExit('QR OTP parameters mismatch')
print('Local fixture QR decode passed')
