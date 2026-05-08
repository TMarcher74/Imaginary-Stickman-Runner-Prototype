import numpy as np
import cv2
from matplotlib import pyplot as plt
# Read image
img = cv2.imread(rf'background\frames\frame_0005.png',cv2.IMREAD_COLOR)

# Convert the image to grayscale
gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

# Find the edges in the image using canny detector
edges = cv2.Canny(img, 100, 110)

plt.subplot(121),plt.imshow(img,cmap = 'gray')
plt.title('Original Image'), plt.xticks([]), plt.yticks([])
plt.subplot(122),plt.imshow(edges,cmap = 'gray')
plt.title('Edge Image'), plt.xticks([]), plt.yticks([])
 
plt.show()

# # Detect points that form a line
# lines = cv2.HoughLinesP(edges, 1, np.pi/180, 68, minLineLength=15, maxLineGap=250)
# # lines = cv2.HoughLinesP(edges, 1, np.pi/90, 68, minLineLength=10, maxLineGap=0)

# # Draw lines on the image
# for line in lines:
#    x1, y1, x2, y2 = line[0]
#    cv2.line(img, (x1, y1), (x2, y2), (0, 255, 0), 3)
# # Show result
# print("Line Detection using Hough Transform")
# cv2.imshow('pic',img)
# cv2.waitKey(0)
# cv2.destroyAllWindows()