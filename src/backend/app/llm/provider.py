"""LLM Provider abstraction — configurable LLM backend."""

from abc import ABC, abstractmethod
from dataclasses import dataclass

from openai import AzureOpenAI

from app.config import settings


@dataclass
class LLMResponse:
    content: str
    model: str
    usage: dict


class LLMProvider(ABC):
    """Abstract base class for LLM providers."""

    @abstractmethod
    def generate(self, system_prompt: str, user_prompt: str, context: dict | None = None) -> LLMResponse:
        """Generate a response from the LLM."""


class AzureOpenAIProvider(LLMProvider):
    """Azure OpenAI implementation."""

    def __init__(self):
        self.client = AzureOpenAI(
            azure_endpoint=settings.azure_openai_endpoint,
            api_key=settings.azure_openai_key,
            api_version=settings.azure_openai_api_version,
        )
        self.deployment = settings.azure_openai_deployment

    def generate(self, system_prompt: str, user_prompt: str, context: dict | None = None) -> LLMResponse:
        messages = [{"role": "system", "content": system_prompt}]

        if context and context.get("data_preview"):
            messages.append({
                "role": "user",
                "content": f"Here is a preview of the dataset:\n```\n{context['data_preview']}\n```",
            })

        messages.append({"role": "user", "content": user_prompt})

        response = self.client.chat.completions.create(
            model=self.deployment,
            messages=messages,
            temperature=0.1,
            max_tokens=4096,
        )

        choice = response.choices[0]
        return LLMResponse(
            content=choice.message.content or "",
            model=response.model,
            usage={
                "prompt_tokens": response.usage.prompt_tokens if response.usage else 0,
                "completion_tokens": response.usage.completion_tokens if response.usage else 0,
                "total_tokens": response.usage.total_tokens if response.usage else 0,
            },
        )


def get_llm_provider() -> LLMProvider:
    """Factory function to get the configured LLM provider."""
    providers = {
        "azure": AzureOpenAIProvider,
    }
    provider_cls = providers.get(settings.llm_provider)
    if not provider_cls:
        raise ValueError(f"Unknown LLM provider: {settings.llm_provider}. Available: {list(providers.keys())}")
    return provider_cls()
