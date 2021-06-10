
# Build the docker image

You can build the memento docker image by running the following command:

```
$ docker build . -t memento
```

Please note: the `Dockerfile` assumes that your user and group id is 1000.
Please edit the file accordingly to your system settings.

# Run memento using docker

With the built image presents on your system, you can use `./cmemento` wrapper to run memento.
Note: it will read (and write) the configuration from `~/.memento` directory. 

If you want to use cmemento from anywhere, just copy the script in a system path:

```
$ sudo cp cmemento /usr/local/bin
```

Example:
```
$ cmemento jira projects
```
