# README: Format

This document outlines the format I want in my README.md files that are stored at the root of the project. The goal of this is to make it human readable and easy to understand. This means:

- concise explainations or instructions,
- subsections, bullet points and numbered lists are preferred over long paragraphs,
- limited bold formatting - never for beginning of headings, bullets, or numbered list items,
- shorter is better than longer,

Each section below will be required unless there is an `(optional)` next to it.

## Project Overview

This section should be a concise overview of the project. It should be no more than 2-3 sentences long. Include the tech stack used and the purpose of the project.

## Setup

This should include how to install. Do not list packages. If there is a custom package that needs to be installed, it should be mentioned here and how to install it. If the project is a TypeScript so we need `npm install` and `npm build`. If it's a Python project, include examples of creating the venv.

Here is an example with a custom package:

1. Ensure the local dependency exists at `../NewsNexus10Db`.
   - To install directly (locally): `npm install file:../NewsNexus10Db`
2. Install dependencies: `npm install`.
3. Build the project: `npm run build`.

## Usage

This section should explain how to use the project. If this is an app that runs on the terminal with arguments, include examples of how to run it with different arguments. If it's a web app, include the URL to access it. If it's a library, include examples of how to use it.

## Project Structure

Use a tree structure to show the project structure. Certain folders do not need to show all files, like an API routes we only need to show at most 5 routes. If there are subfolders, show those and only a few files in each subfolder. Here is an example:

```
PersonalWeb03-API/
├── src/
│   ├── routers/
│   │   ├── auth.py       # Authentication endpoints
│   │   └── blog.py       # Blog endpoints
│   ├── models.py         # SQLAlchemy database models
│   ├── schemas.py        # Pydantic validation schemas
│   ├── auth.py           # Authentication utilities
│   ├── database.py       # Database configuration
│   └── main.py           # FastAPI application
├── docs/
│   └── API_REFERENCE.md
├── requirements.txt
├── .env
├── .env.example
└── README.md
```

## .env

This section should just show the environment variables used in the project. Include the value of the environment variables if they are not secret. Here is an example:

```
NAME_APP=NewsNexus10
JWT_SECRET=
NAME_DB=newsnexus10.db
PATH_DATABASE=/home/shared/databases/NewsNexus10/
```

## External Files (optional)

If usage requires external files, such as a spreadsheet, text file, etc. Create a sub section for each file. Include the naming convention and the expected contents of the file. If it is a spreadsheet that the project will read from, include the column headers and what each column is used for. If it is a spreadsheet that the project will write to, explain the output columns. If a JSON file is used or made, include the structure of the file. Keep this section concise - short is better than long.

## Child Processes (optional)

If the project spawns child processes, include a sub section for each child process. List the related .env variables and how logging is handled for that process. Keep this section concise - short is better than long.

## References

My projects will usually have instructions for logging (i.e. docs/LOGGING_NODE_JS_V06.md) or other instructions in the docs folder. Include a reference to those files here. No need to explain what they are, just reference them with links so when the project is on GitHub, the links work.
