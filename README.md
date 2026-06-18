# OctoCount
This addon adds a display of the number of octopi online by using the ".server info" command every minute.    
Detailed information will be shown on mouse over.    
Left click the display to show a graph of saved player counts. The graph can show the last 120 minute samples, seven days of hourly averages, or 30 days of daily averages. Hover over a bar to see its time and count.    
Click a bar in the Days view to inspect that date using 1, 5, 15, 30, or 60 minute averages.    
History is kept separately for each realm for 30 days in WoW's `OctoCountDB` saved variable.    
Overview data uses compact rolling buckets. Per-realm minute values are retained so any saved day can be inspected at different intervals.    
Each realm is stored directly under its realm name, for example `OctoCountDB["Realm Name"]`.    
You can move the display by dragging while holding CTRL and SHIFT.    
To reset the position of the display, right click the display while holding CTRL and SHIFT.    
