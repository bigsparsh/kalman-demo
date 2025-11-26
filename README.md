# Indoor Navigation System

This is an indoor navigation application, which used PDR (Person Dead Reckoning) to estimate the user's position in an indoor environment. To correct the data we use the Kalman Filter.

### Important Info
- The Application is made using flutter with flutter_map.
- There is path recording feature where user can first walk the path they want to make.
- The path when made will be a straight line on which the map marker will snap to.
- Whenver the marker is snapped on an existing path, and then they hit record again then a point from their exact location will be made and they will be allowed to move to the location they want to and then another path will be recorded.
- The path are stored as vertices and edges.
- If two paths are intersecting each other then there should be a vertex at the intersection.
- Whenever snapped and move forward beyond the path, then stop registering the movement.