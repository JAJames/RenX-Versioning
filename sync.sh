#!/bin/bash
lockfile=/home/renx/static.renegade-x.com/sync.lock
{
  if ! flock -n 9
  then
    exit 1
  fi

echo Synching...
s3cmd sync --acl-public --add-header="Cache-Control:max-age=0" --config=/home/renx/static.renegade-x.com/.s3cfg-gcloud /home/renx/static.renegade-x.com/data/ s3://static.renegade-x.com/
# "--delete-removed" was removed due to a 400 InvalidArgument error; that functionality needs to be re-added somehow

} 9>"$lockfile"
