-- Color Initialization
GREEN = {["red"] = 0, ["green"] = 255, ["blue"] = 0}		-- food
MAGENTA = {["red"] = 255, ["green"] = 0, ["blue"] = 255}	-- room 0
BLUE = {["red"] = 0, ["green"] = 0, ["blue"] = 255}		-- room 1
ORANGE = {["red"] = 255, ["green"] = 140, ["blue"] = 0}	-- room 2
RED = {["red"] = 255, ["green"] = 0, ["blue"] = 0}			-- room 3

-- Rooms array for debugging
rooms = {"MAGENTA", "BLUE", "ORANGE", "RED"}

-- Representation of the available resources
NEST = 0	-- central room
SITE_0 = 1	-- LED placed on room 0 entrance (MAGENTA)
SITE_1 = 2	-- LED placed on room 1 entrance (BLUE)
SITE_2 = 3	-- LED placed on room 2 entrance (ORANGE)
SITE_3 = 4	-- LED placed on room 3 entrance (RED)
FOOD = 5		-- green LEDs placed in the room

-- States
INIT = "INIT"		-- initially, when robot has no opinion, randomly select an opinion
AVOID = "AVOID"		-- state to avoid collisions. Collisions are avoided by smooth transition of direction using proximity sensor
SURVEY = "SURVEY"	-- survey the room with the chosen opinion
WAGGLE = "WAGGLE"	-- waggle dance (broadcast) the opinion

current_state = INIT	-- current state of the robot. Change it, when ever the state changes
current_position = NEST	-- positions of the robot

-- Robot's opinion (room chosen) 
opinion = nil		-- room choice

-- collision avoidance parameters
resume_state = INIT			-- state to be restored when collision avoided
is_obstacle_sensed = false	-- if obstacle found set it to true
collision_index = nil		-- index of the proximity sensor that found the collision

-- room sensing parameters
is_room_sensed = false	-- when an LED (the opinion of the robot) at the entrance has to be sensed to enter or exit the room, set it to true 
is_at_entrance = false 	-- robot near the LED (opinion)
is_entered_room = false	-- set if robot has entered into the room for survey
room_angle = nil			--	angle to the LED (opinion)
room_distance = nil		-- distance to the LED (opinion)

-- Problem specific metrics
food_count = 0	-- number of food sources found
v_O = 0	-- evaluation of number of food sources found (min:2, max: 12) - eval: 0.1 * food_count - 0.2
v_G = 0	-- ground sensor value
v_L = 0	-- light sensor value
v	= 0	-- average of metrics

SPEED = 20 -- base speeed

-- Application specific parameters
LAM = -2		-- lambda (rate) value for probability exponential distribution
SCALE = 40	-- weight for probability exponential distribution

-- Walk time parameters
max_walk_steps = nil		-- The total number of steps robot can take when entered into desired state
MAX_RAND_WALK_STEPS = 30	-- Maximum number of steps before changing the direction
rand_walk_steps = nil		-- Random number of steps before changing the direction
BASE_PROBABILITY = 0.2	-- Base probability to change the opinion


--[[***function avoidCollision()***
Avoid collisions upon detection.
]]
function avoidCollision()
	if collision_index ~= nil then	-- collision found
		if collision_index <= 12 then	-- obstacle on the left side
			robot.wheels.set_velocity(SPEED, (collision_index - 1) * SPEED / 11)	-- Steer right by decreasing the right wheel speed
		else -- obstacle on the right side
			robot.wheels.set_velocity((24 - collision_index) * SPEED / 11, SPEED) -- Steer left by decreasing the left wheel speed
		end
		is_obstacle_sensed = false
		current_state = resume_state
	end
end


--[[ This function is executed only once, when the robot is removed
     from the simulation ]]
function destroy()
   -- nothing to do here
end


--[[***function detectCollision()***
Sense obstacles by sensing the proximity sensor with heighest value.
Update global parameters is_obstacle_sensed, collision_index based on the obstacles sensed. 
]]
function detectCollision()
   -- Initialization: index and value for proximity sensors with highest value
	local value = -1	-- highest value found so far
	local index = -1	-- index of the highest value

	local leds, food = sepLedsAndFood()	-- separate LEDs(at the entrance), and food (green LEDs)

	-- If robot in the desired room, do not allow it to go out of room
	if is_entered_room then	-- if robot within the desired room
		if next(leds) ~= nil then	-- if LEDs not empty
			table.sort(leds, function(a,b) return a.distance < b.distance end)	-- sort LEDs by increasing order of distance
			if leds[1].distance <= 40 then	-- if robot is close to the LED
				value = 1	-- set value other than 0
				if leds[1].angle > 0 then	-- if positive angle
					index = math.floor(leds[1].angle / 0.2618) + 1 -- set index in range 1 and 12
				else
					index = 24 - math.floor(math.abs(leds[1].angle) / 0.2618)	-- set index 13 and 24
				end
			end 
		end
	end

	-- Update value and index by checking each proximity sensor (1 to 24).
	for i = 1, 24 do	-- By the end of this loop value contains the highest value of sensor and index contains it's index.
		-- Update value and index when ever the previous value is lower than the current proximity sensor value
		if value < robot.proximity[i].value then 
			value = robot.proximity[i].value
			index = i
		end
	end

	-- Update global paramaters for collision avoidance based on the highest proximity sensor value found
	if value == 0  then	-- No obstacle
		is_obstacle_sensed = false
		collision_index = nil
		current_state = resume_state
	else	-- obstacle found
		is_obstacle_sensed = true
		collision_index = index
	end
end


--[[***function eqOpinion()***
Equally distribute an opinion of available rooms.
Update global parameter opinion on selection.
]]
function eqOpinion()
	id = string.sub(robot.id, 4)
	if robot.motor_ground then
		opinion = math.fmod(id - 1, 4) + 1
	end

	if robot.light then
		opinion = 4 - math.fmod(id + 1, 4)
	end
end


--[[***function executeAndFlipState()***
Execute the current state and flip when timeout. 
]]
function executeAndFlipState(curr_state)
	if curr_state == SURVEY then	-- SURVEY state
		if max_walk_steps == nil then	-- if no max walk steps
			max_walk_steps = robot.random.uniform_int(150, 300)	-- update max walk steps
		
		elseif max_walk_steps <= 0 then -- walked max steps
			max_walk_steps = nil	-- reset max walk steps

			is_room_sensed = false	--reset is_room_sensed flag
			is_at_entrance = false	-- reset is_at_entrance flag
			is_entered_room = false	-- reset is_entered_room flag

			current_state = WAGGLE	-- switch state to WAGGLE
			resume_state = WAGGLE		-- set resume_state to WAGGLE to recover when collision detected
		
		elseif max_walk_steps > 0 then	-- if not reached max walk steps
			updateMetrics()	-- update metrics
		end
	
	elseif curr_state == WAGGLE then	-- WAGGLE state
		if max_walk_steps == nil then	-- if no max walk steps
			max_walk_steps = math.ceil(SCALE * LAM * (1 - math.exp(- LAM * v)))	-- update max walk steps
			--log("W:"..robot.id..": o:"..rooms[opinion]..", v:"..v.."mws:"..max_walk_steps)

		elseif max_walk_steps <= 0 then	-- walked max steps
			max_walk_steps = nil	-- reset max walk steps
			local neighbors_opinion = {}	-- empty table to read neighbors opinion
			for i = 1, #robot.range_and_bearing do -- for each robot sense
				if robot.range_and_bearing[i].range < 300 and robot.range_and_bearing[i].data[1] ~= 0 then -- see if they are close enough. What happens if we don't put a distance cutoff here?
					table.insert(neighbors_opinion, robot.range_and_bearing[i].data[1]) -- insert opinion into table
				end
			end

			if robot.random.uniform() > BASE_PROBABILITY then	-- probability to change the opinion
				if next(neighbors_opinion) ~= nil then	-- neighbors not empty
					opinion = neighbors_opinion[robot.random.uniform_int(1, #neighbors_opinion + 1)]	-- adopt opinion
				end
			end

			is_room_sensed = false	--reset is_room_sensed flag
			is_at_entrance = false	-- reset is_at_entrance flag
			is_entered_room = false	-- reset is_entered_room flag

			-- reset metrics
			food_count = 0	-- number of food sources found
			v_O = 0	-- evaluation of number of food sources found (min:2, max: 12) - eval: 0.1 * food_count - 0.2
			v_G = 0	-- ground sensor value
			v_L = 0	-- light sensor value
			v	= 0	-- average of metrics

			current_state = SURVEY	-- switch state to SURVEY
			resume_state = SURVEY		-- set resume_state to SURVEY to recover when collision detected

		elseif max_walk_steps > 0 then	-- if not reached max walk steps
			-- do nothing
		end
	end
	robot.wheels.set_velocity(SPEED, SPEED)
end


--[[***function getIntoNest()***
Get into the nest by moving away from the LED of opinion towards any other LED
]]
function getIntoNest()
	local rotation_speed = 0	-- wheels rotation speed
	is_room_sensed = false	-- reset is_room_sensed flag

	leds, food = sepLedsAndFood()	-- separate LEDs(at the entrance), and food (green LEDs)
	
	if next(leds) ~= nil then	-- leds not empty
		for i = 1, #leds do	-- for each LED
			if leds[i].object_type == opinion then -- LED matches the opinion
				room_angle = leds[i].angle	-- update global parameter room_angle
				room_distance = leds[i].distance	-- update global paramter room_distance				
			end
		end
		table.sort(leds, function(a,b) return a.distance > b.distance end) -- leds food in decreasing order
		if math.abs(leds[1].angle) > 0.0872 then	-- led angle out of threshold
			if leds[1].angle > 0 then --positive angle (led on left)
				rotation_speed = (leds[1].angle * robot.wheels.axis_length) / 2.0	-- calculate rotatoon speed
				robot.wheels.set_velocity(-rotation_speed, rotation_speed)	-- left rotation (half on left and the remaining half on the right wheel in opposite directions)
			else	-- negative angle (led on right)
				rotation_speed = (math.abs(leds[1].angle) * robot.wheels.axis_length) / 2.0	-- calculate rotatoon speed
				robot.wheels.set_velocity(rotation_speed, -rotation_speed)	-- right rotation (half on left and the remaining half on the right wheel in opposite directions)
			end
		else	-- led angle within threshold
			if leds[1].distance <= 250 and room_distance >= 50 then -- led distance within threshold
				is_room_sensed = false
				is_at_entrance = false -- reset falg is_robot_at_entrance 
				is_entered_room = true	-- the robot has moved to the desired room (site)
				current_position = NEST -- set current position to the entered nest
				robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
			else	-- food d	istance not in threshold
				robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
			end
		end
	else
		robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
	end
end


--[[***function getIntoRoom()***
Get into the room by moving close to a food source (green LED)
]]
function getIntoRoom()
	local rotation_speed = 0	-- wheels rotation speed
	is_room_sensed = false	-- reset is_room_sensed flag

	local leds, food = sepLedsAndFood()	-- separate LEDs(at the entrance), and food (green LEDs)
	
	if next(food) ~= nil then	-- food not empty
		table.sort(food, function(a,b) return a.distance < b.distance end) -- sort food in increasing order
		if math.abs(food[1].angle) > 0.0872 then	-- food angle out of threshold
			if food[1].angle > 0 then --positive angle (food on left)
				rotation_speed = (food[1].angle * robot.wheels.axis_length) / 2.0	-- calculate rotatoon speed
				robot.wheels.set_velocity(-rotation_speed, rotation_speed)	-- left rotation (half on left and the remaining half on the right wheel in opposite directions)
			else	-- negative angle (food on right)
				rotation_speed = (math.abs(food[1].angle) * robot.wheels.axis_length) / 2.0	-- calculate rotatoon speed
				robot.wheels.set_velocity(rotation_speed, -rotation_speed)	-- right rotation (half on left and the remaining half on the right wheel in opposite directions)
			end
		else	-- food angle within threshold
			if food[1].distance <= 40 then -- food d	istance within threshold
				is_room_sensed = false
				is_at_entrance = false -- reset falg is_robot_at_entrance 
				is_entered_room = true	-- the robot has moved to the desired room (site)
				current_position = opinion -- set current position to the entered room
				robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
			else	-- food d	istance not in threshold
				robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
			end
		end
	else
		robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
	end
end


--[[***function headToLED()***
Change the angle and movement of the robot towards the LED upon sensing the room.
NOTE: angle (in radians) * distance between wheels gives the direction of the object.
]]
function headToLED()
	local rotation_speed = 0
	senseRoom()
	if room_angle ~= nil and room_distance ~= nil then
		if math.abs(room_angle) > 0.0872 then	-- room angle out of threshold
			if room_angle > 0 then --positive angle (LED on left)
				rotation_speed = (room_angle * robot.wheels.axis_length) / 2.0	-- calculate rotatoon speed
				robot.wheels.set_velocity(-rotation_speed, rotation_speed)	-- left rotation (half on left and the remaining half on the right wheel in opposite directions)
			else	-- negative angle (LED on right)
				rotation_speed = (math.abs(room_angle) * robot.wheels.axis_length) / 2.0	-- calculate rotatoon speed
				robot.wheels.set_velocity(rotation_speed, -rotation_speed)	-- right rotation (half on left and the remaining half on the right wheel in opposite directions)
			end
		else	-- room angle within threshold
			if room_distance <= 20 then	-- room distance within threshold
				is_room_sensed = false
				is_at_entrance = true -- robot near the LED
				is_entered_room = false
			else	-- room distance out of threshold
				robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
			end
		end
	else
		robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
	end
end


--[[ This function is executed every time you press the 'execute'
     button ]]
function init()
	opinion = nil		-- room choice

	resume_state = INIT			-- state to be restored when collision avoided
	is_obstacle_sensed = false	-- if obstacle found set it to true
	collision_index = nil			-- index of the proximity sensor that found the collision

	is_room_sensed = false	-- when an LED (the opinion of the robot) at the entrance has to be sensed to enter or exit the room, set it to true 
	room_angle = nil			--	angle to the LED (opinion)
	room_distance = nil		-- distance to the LED (opinion)
	is_at_entrance = false -- robot near the LED (opinion)
	is_entered_room = false	-- set if robot has entered into the room for survey


	food_count = 0	-- number of food sources found
	v_O = 0	-- evaluation of number of food sources found (min:2, max: 12) - eval: 0.1 * food_count - 0.2
	v_G = 0	-- ground sensor value
	v_L = 0	-- light sensor value
	v	= 0	-- average of metrics

	max_walk_steps = nil	-- The total number of steps robot can take when entered into desired state	
	rand_walk_steps = nil	-- Random number of steps before changing the direction

	-- enable omnidirectional camera to detect resources
	robot.colored_blob_omnidirectional_camera.enable()
end


--[[***function objectType(object)***
	Finds the object and returns an integer value representing the object type
	params:	object with red, green, and blue values
	return:	1 - room 0 (magenta)
				2 - room 1 (blue)
				3 - room 2 (orange)
				4 - room 3 (red)
				5 - food (green)
				nil - unknown object	]]
function objectType(object)
	-- Food (green)
	if (	object.color.red == GREEN.red and 
			object.color.green == GREEN.green and 
			object.color.blue == GREEN.blue ) then
		return FOOD
	-- Room 0 (magenta)
	elseif ( object.color.red == MAGENTA.red and 
				object.color.green == MAGENTA.green and 
				object.color.blue == MAGENTA.blue ) then
		return SITE_0
	-- Room 1 (blue)split code in multiple lines
	elseif ( object.color.red == BLUE.red and 
				object.color.green == BLUE.green and 
				object.color.blue == BLUE.blue ) then
		return SITE_1
	-- Room 2 (orange)
	elseif ( object.color.red == ORANGE.red and 
				object.color.green == ORANGE.green and 
				object.color.blue == ORANGE.blue ) then
		return SITE_2
	-- Room 3 (red)
	elseif ( object.color.red == RED.red and 
				object.color.green == RED.green and 
				object.color.blue == RED.blue ) then
		return SITE_3
	else
		return false
	end
end


--[[***function processState(curr_state)***
Process the current state by using the flags is_obstacle_sensed, is_room_sensed, is_at_entrance, is_entered_room
]]
function processState(curr_state)
	if is_obstacle_sensed then	-- collision detected
		--log(robot.id..": avoid collision")
		setDataCollisionAvoid()	-- save current state to restore after avoiding collision
	elseif is_room_sensed then
		--log(robot.id..": head to led")
		headToLED()	-- head towards the direction of the LED
	elseif is_at_entrance then
		if curr_state == SURVEY then
			--log(robot.id..": get into room")
			getIntoRoom()	-- randomly choose a green LED (food) and move towards it
		elseif curr_state == WAGGLE then
			getIntoNest()
		end
	elseif is_entered_room then
		--log(robot.id..": entered room")
		executeAndFlipState(curr_state)
		randomWalk()
	else
		senseRoom()	-- sense the room of opinion
	end			
end


--[[***function randomOpinion()***
Randomly choose an opinion of available rooms.
Update global parameter opinion on selection.
]]
function randomOpinion()
	local leds, food = sepLedsAndFood()	-- separate LEDs(at the entrance), and food (green LEDs)

	if next(leds) ~= nil then	-- LEDs not empty
		opinion = leds[robot.random.uniform_int(1, #leds + 1)].object_type	-- randomly choose an LED
	end
end


--[[***function randomOpinion()***
Randomly change the direction of robot
]]
function randomWalk()
	if rand_walk_steps == nil then
		rand_walk_steps = robot.random.uniform_int(MAX_RAND_WALK_STEPS + 1)
	elseif rand_walk_steps <= 0 then
		rand_walk_steps = nil
		local turn_steps = robot.random.uniform_int((2 *SPEED) + 1)
		robot.wheels.set_velocity(-turn_steps, turn_steps)
	elseif rand_walk_steps >0 then
		rand_walk_steps = rand_walk_steps - 1
		robot.wheels.set_velocity(SPEED, SPEED)
	end
end


--[[ This function is executed every time you press the 'reset'
     button in the GUI. It is supposed to restore the state
     of the controller to whatever it was right after init() was
     called. The state of sensors and actuators is reset
     automatically by ARGoS. ]]
function reset()
end


--[[***function senseRoom()***
Sense the room of opinion.
Update glibal parameters is_room_sensed, room_angle, room_distance upon sensing the LED (opinion).
]]
function senseRoom()
	local leds, food = sepLedsAndFood()	-- separate LEDs(at the entrance), and food (green LEDs)
	room_angle = nil	-- init room angle
	room_distance = nil	-- init room distance
	if next(leds) ~= nil then	-- if LEDs not empty
		for i = 1, #leds do	-- for each LED
			if leds[i].object_type == opinion then -- LED matches the opinion
				is_room_sensed = true	-- room sensed set global parameter
				is_at_entrance = false
				is_entered_room = false
				room_angle = leds[i].angle	-- update global parameter room_angle
				room_distance = leds[i].distance	-- update global paramter room_distance				
			end
		end
	end
end


--[[***function sepLedsAndFood()***
Separate LEDs(at the entrance), and food (green LEDs).
]]
function sepLedsAndFood()
	local objects = table.copy(robot.colored_blob_omnidirectional_camera)	-- copy objects found using omnidirectional camera
	
	local leds = {}	-- empty table to store LEDs data
	local food = {}	-- empty table to store food data
	local led_count = 0	-- init LED count
	local food_count = 0	-- init food count
	
	for i = 1, #objects do	-- for each object found
		object_type = objectType(objects[i])	-- determine the object type (food or red led color)
		if object_type then
			if object_type == FOOD then	-- object type is food
				food_count = food_count + 1	-- increment food count
				local tmp = {}	-- temporary table to hold the current object data
				tmp["object_type"] = object_type	-- store object type
				tmp["distance"] = objects[i].distance	-- store distance to the object
				tmp["angle"] = objects[i].angle	-- store angle to the object
				food[food_count] = tmp	-- store temp data to master table
			elseif object_type >= SITE_0 and object_type <= SITE_3 then -- object type is an LED
				led_count = led_count + 1	-- increment LED count
				local tmp = {}	-- temporary table to hold the current object data
				tmp["object_type"] = object_type	-- store object type
				tmp["distance"] = objects[i].distance	-- store distance to the object
				tmp["angle"] = objects[i].angle	-- store angle to the object
				leds[led_count] = tmp	-- store temp data to master table
			end
		end
	end	
	return leds, food	-- return separated LED and food tables
end


--[[***function setDataCollisionAvoid(state)***
Save previous state to recover from collision avoidance state.
]]
function setDataCollisionAvoid()
	resume_state = current_state	-- store current state to restore later
	current_state = AVOID	-- change state to avoid
end


--[[ This function is executed at each time step
     It must contain the logic of your controller ]]
function step()
	detectCollision() -- If collision detected, current state is set to AVOID
	if max_walk_steps ~= nil then	-- if max_walk_steps has a value
		max_walk_steps = max_walk_steps - 1 -- decrement max walk steps
	end

	-- AVIOID STATE --
	if current_state == AVOID then
		avoidCollision()	-- move out of obstacles

	-- SURVEY STATE--
	elseif current_state == SURVEY then
		robot.range_and_bearing.set_data(1,0)	-- stop broadcasting opinion
		processState(SURVEY)

	-- WAGGLE DANCE STATE --
	elseif current_state == WAGGLE then
		robot.range_and_bearing.set_data(1,opinion)	-- broadcast opinion
		processState(WAGGLE)
	
	--	INIT STATE--
	elseif current_state == INIT then
		if is_obstacle_sensed then	-- collision detected
			setDataCollisionAvoid()	-- save the INIT state to restore after avoiding collision
		else
			robot.wheels.set_velocity(SPEED, SPEED)	-- go straight
			--randomOpinion()	-- randomly choose an opinion
			-- OR --
			eqOpinion()
			-- log(robot.id..": opinion: "..rooms[opinion])	-- DEBUG: robot's opinion
			if opinion ~= nil then	-- if robot has an opinion
				current_state = SURVEY	-- change to SURVEY state
				resume_state = SURVEY
				is_room_sensed = false
				is_at_entrance = false
				is_entered_room = false
			end
		end
	else
		log(robot.id..": something is wrong")
		-- robot.wheels.set_velocity(0,0)
	end
--[[
	if opinion ~= nil then
		if opinion == 1 then
			robot.leds.set_all_colors(205, 0, 205)
		elseif opinion == 2 then
			robot.leds.set_all_colors(85, 26, 139)
		elseif opinion == 3 then
			robot.leds.set_all_colors(238, 238, 0)
		elseif opinion == 4 then
			robot.leds.set_all_colors(128, 0, 0)
		else
			log(robot.id..": something wrong")
		end
	end
]]
	if opinion ~= nil then
		log(robot.id..":"..opinion - 1)
	end
end


-- function used to copy two tables
function table.copy(t)
  local t2 = {}
  for k,v in pairs(t) do
    t2[k] = v
  end
  return t2
end


--[[***function setDataCollisionAvoid(state)***
Save previous state to recover from collision avoidance state.
]]
function updateMetrics()
	local tmp_food_count = 0 -- temporary value for food count

	local leds, food = sepLedsAndFood()	-- separate LEDs(at the entrance), and food (green LEDs)
	
	if next(food) ~= nil then	-- food not empty
		for i = 1, #food do	-- for each food (green LED)
			if food[i].distance <= 150 then	-- if distance within threshold
				tmp_food_count = tmp_food_count + 1	-- increment food count
			end
		end
	end

	-- All robots
	if tmp_food_count > food_count then	-- update global parameter v_O whenever new food found
		food_count = tmp_food_count	-- update food count if new food found
		v_O = (0.1 * food_count) - 0.2	-- evaluate v_O using food count
		--log(robot.id..": Opinion:"..rooms[opinion]..", Food eval:"..v_O)
	end

	-- Type G robot
	if robot.motor_ground then	-- if robot has ground sensor, it is of type G
		ground = table.copy(robot.motor_ground)	-- copy ground sensor values
		table.sort(ground, function(a,b) return a.value > b.value end)	-- sort ground sensor values in increasing order
		if ground[1].value > v_G then	-- consider the maximum value of ground sensor
			v_G = ground[1].value	-- set v_G to max ground sensor value
			-- log(robot.id..": Opinion:"..rooms[opinion]..": Ground:"..v_G)
		end
	end

	-- Type L robot
	if robot.light then	-- if robot has light sensor, it is of type L
		light = table.copy(robot.light)	-- copy light sensor values
		table.sort(light, function(a,b) return a.value > b.value end)	-- sort light sensor values in increasing order
		if light[1].value > v_L then	-- consider the maximum value of light sensor
			v_L = light[1].value	-- set v_L to max light sensor value
			-- log(robot.id..": Opinion:"..rooms[opinion]..": Light:"..v_L)
		end
	end

	v = (v_G + v_L + v_O) / 2	-- calculate average value (denominator 2 because the robot has either v_G or v_L, but not both)
end