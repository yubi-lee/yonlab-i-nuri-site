from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserCreate(BaseModel):
    email: EmailStr
    name: str = Field(min_length=2, max_length=80)
    password: str = Field(min_length=10, max_length=128)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    email: EmailStr
    name: str
    role: str


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    refresh_token: str
    user: UserOut


class ResourceWrite(BaseModel):
    title: str = Field(min_length=2, max_length=180)
    summary: str = Field(min_length=2, max_length=500)
    body: str = Field(min_length=2)
    audience: str = Field(min_length=2, max_length=60)
    resource_type: str = Field(min_length=2, max_length=60)
    category_id: str
    status: str = "draft"
    featured: bool = False
    tag_ids: list[str] = []


class InquiryCreate(BaseModel):
    email: EmailStr
    subject: str = Field(min_length=2, max_length=180)
    message: str = Field(min_length=10, max_length=5000)
    privacy_agreed: bool


class InquiryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    email: EmailStr
    subject: str
    message: str
    status: str
    admin_note: str
    created_at: datetime
