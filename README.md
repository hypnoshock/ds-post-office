# A Post Office (in Downstream)

An attempting at making a post office for the game Downstream.

When using the building as a customer you are able to select one of your equipped bags, address it to a specific Mobile Unit and select which post office it should be delivered to. When sending a bag you are able to also specify an additional bag which will be used as payment for the postman/courier. If there are any bags addressed to you sat at the post office, you can collect them all using the `Collect Bags` button from the customer menu

When using the building as a postman you are able to collect bags that are sat the office which are destined for another post office. After collecting the bags you will see the bags in your inventory however you will not be able to manipulate the contents as they do not belong to you. When you drop off the bag(s) at the destination office via the postman menu you will keep any bags that were marked as payment bags.

## Problems

- The way I'm storing state means that the frontend cannot display the information about the bags that are sat at the office. This means as a customer you don't know if there are any bags waiting for you and as a postman there isn't any way of knowing which post office the bag should be delivered to!!
- I'm manipulating state directly which means this example should be used as inspiration for future rules that we want to implement in Downstream. I've tried to keep the tranfser of ownership of bags in line with a rule that could one day be possible i.e. bag owners are allowed to set the owner of a bag and bag owners are allowed to equip the bag to anything in the game
