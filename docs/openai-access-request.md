# OpenAI access request — draft, not submitted

Form: https://openai.com/form/sign-in-with-chatgpt-interest/

Requested capability: **Sign in and ChatGPT plan use for AI requests**.

## Product description

We are developing a native macOS application for statistical analysis of Apple Photos libraries. The application reads locally available library metadata, including records whose original images are stored in iCloud, and produces interactive charts and tables covering camera and lens usage, focal lengths, exposure settings, dates and locations where available.

We intend to publish the source under an open-source licence and offer a paid, packaged release through the Mac App Store, subject to technical validation and App Review. We are requesting confirmation that this paid distribution can integrate Sign in with ChatGPT and eligible users' ChatGPT plan usage, and any approval required before offering that integration.

Users would ask questions such as “Show the number of pictures by focal length, split by camera.” The model would translate the question into a structured, validated analysis request. The application would execute that request against its local metadata index and render the chart. The intended design does not require uploading original images or the full library database. Model inputs would include the question and available field definitions, with aggregate query results supplied when needed for explanations.

Core analysis and charts would work locally without signing in. The optional AI feature would clearly identify ChatGPT plan usage and provide usage-management controls.

Project repository: https://github.com/buildingafuckingdeathstar/photos-statistics

## Required details still missing

- Work email
- First and last name
- Company or developer name
- Website URL (confirm whether the repository URL is suitable)
- Final product name, if chosen
- Job title (optional)

## Eligibility basis

The [official plan-usage documentation](https://developers.openai.com/siwc/token-sharing-open-source) directs paid apps to the interest form. The [integration cookbook](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt) likewise says to request access before offering the integration in a paid app. Publishing source does not establish a paid edition's eligibility.
