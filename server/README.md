##API Reference
------

###Server
------

1. **Check if server is running:**  
    a. Type: **GET**  
    b. Path: **/**  
    c. Parameters: **None**  
    d. Returns: **It's running**
    
###User Manipulation
------

<ol type="1">
    <li><b>Create an user:</b>
        <ol type="a">
            <li>Type: <b>POST</b></li>
            <li>Path: <b>/Users/Create/</b></li>
            <li>Parameters:
                <ol type="i">
                    <li><b>full_name</b></li>
                    <li><b>username</b></li>
                    <li><b>password</b></li>
                </ol>
            </li>
            <li>Returns: <b>OK</b></li>
        </ol>
    </li>
    
    <li><b>List avalaible users:</b>
        <ol type="a">
            <li>Type: <b>GET</b></li>
            <li>Path: <b>/Users/List/</b></li>
            <li>Parameters:
                <ol type="i">
                    <li><b>filter</b> (Optional, used to filter the search. If doesn't appear it will return all the available users)</li>
                </ol>
            </li>
            <li>Returns:
                <ol type="i">
                    <li><b>[]</b> (If no match)</li>
                    <li><b>[{"full_name": "<FULLNAME>, "username": "<USERNAME>"}, ...]</b></li>
                </ol>
            </li>
        </ol>
    </li>
    
    <li><b>Delete an user:</b>
        <ol type="a">
            <li>Type: <b>POST</b></li>
            <li>Path: <b>/Users/Delete/</b></li>
            <li>Parameters:
                <ol type="i">
                    <li><b>username</b></li>
                </ol>
            </li>
            <li>Returns: <b>OK</b></li>
        </ol>
    </li>
</ol>

###Error Handling
-------

Whatever procedure you execute has an error message associated, the format is the following:

    ERROR: <Message_for_that_procedure>
    
If the server is in **DEBUG** mode, the format will be the following:

    ERROR: <Message_for_that_procedure>\n <Server's_Exception>
    
    
###Running the tests
-------

**Warning:** The set of test cases will drop the postgresql schema in order to work with a clean database.