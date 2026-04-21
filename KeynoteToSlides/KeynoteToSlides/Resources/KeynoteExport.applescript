-- KeynoteExport.applescript
-- Called by KeynoteToSlides via NSUserAppleScriptTask.
-- argv item 1: POSIX path to the .key source file
-- argv item 2: POSIX path for the .pptx output file
on run argv
    set keynotePath to item 1 of argv
    set pptxPath to item 2 of argv
    tell application "Keynote"
        set targetDoc to open POSIX file keynotePath
        repeat 60 times
            try
                if (count of slides of targetDoc) > 0 then exit repeat
            end try
            delay 0.5
        end repeat
        export targetDoc to POSIX file pptxPath as Microsoft PowerPoint
        close targetDoc saving no
    end tell
end run
